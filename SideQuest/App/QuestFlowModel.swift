import Foundation
import Observation
import UIKit
import CoreLocation

/// Drives one quest from "Give me a quest" to the result screen.
@MainActor
@Observable
final class QuestFlowModel {
    enum Phase: Equatable {
        case idle
        /// Busy with a playful status line ("Finding real places near you…").
        case working(String)
        /// A quest is on the table: accept or reroll.
        case offered
        /// Accepted; waiting for a photo.
        case active
        case verifying(String)
        /// People were spotted: show the face-blurred photo before anything is sent.
        case reviewing
        /// Verdict on screen.
        case result
    }

    /// A photo waiting for the player's OK on the review screen.
    struct PendingPhoto {
        var resized: UIImage
        var redacted: UIImage
        var detectedRegions: [CGRect]
        var extraRegions: [CGRect] = []
        var faceCount: Int
        var personCount: Int
        var detectionFailed = false
    }

    private(set) var phase: Phase = .idle
    private(set) var activeQuest: ActiveQuest? { didSet { persistActiveQuest() } }
    private(set) var verdict: Verdict?
    private(set) var outcome: CompletionOutcome?
    /// The blurred photos that were checked (shown on the result screen).
    private(set) var photos: [UIImage] = []
    var photo: UIImage? { photos.first }
    /// A one-off message (geofence, duplicate photo, errors).
    var notice: String?
    var errorMessage: String?
    /// True when an "unsure" photo was counted as a pass without a retake.
    private(set) var passedOnBenefitOfDoubt = false
    private(set) var lastAttempts = 1

    /// Photos waiting for the player's OK on the review screen.
    private(set) var pendingPhotos: [PendingPhoto] = []
    private var preparedJPEGs: [Data] = []
    private var photoHashes: [UInt64] = []
    private var lastTestOutcome: Verdict.Outcome?
    private var placesCache: (scope: QuestScope, theme: QuestTheme?, location: CLLocation, date: Date, places: [Place], areaName: String?)?
    private var currentTask: Task<Void, Never>?

    let settings: AppSettings
    let tracker: AIUsageTracker
    let location: LocationService
    let store: ProgressStore
    private let placesService = PlacesService()
    private let defaults: UserDefaults

    init(settings: AppSettings, tracker: AIUsageTracker, location: LocationService, store: ProgressStore,
         defaults: UserDefaults = .standard) {
        self.settings = settings
        self.tracker = tracker
        self.location = location
        self.store = store
        self.defaults = defaults
        restoreActiveQuest()
    }

    var isBusy: Bool {
        switch phase {
        case .working, .verifying: return true
        default: return false
        }
    }

    // MARK: Provider

    func makeProvider(testPhotoOutcome: Verdict.Outcome? = nil) -> AIProvider {
        switch settings.providerKind {
        case .demo:
            var mock = MockAIProvider(verdictMode: settings.mockVerdictMode,
                                      injectInvalidFirstQuest: settings.mockInjectInvalidQuest,
                                      testPhotoOutcome: { testPhotoOutcome },
                                      usage: tracker.sink)
            #if DEBUG
            // Screenshots: pick a specific demo quest with `-mockForcedQuest "<title>"`.
            mock.forcedTitle = UserDefaults.standard.string(forKey: "mockForcedQuest")
            mock.placeHint = UserDefaults.standard.string(forKey: "mockPlaceHint")
            #endif
            return mock
        case .claude:
            return ClaudeProvider(client: AnthropicClient(apiKey: { APIKeyStore.claudeKey() }),
                                  generationModel: settings.generationModel,
                                  usage: tracker.sink)
        case .gemini:
            return GeminiProvider(client: GeminiClient(apiKey: { APIKeyStore.geminiKey() }),
                                  model: settings.geminiModel,
                                  usage: tracker.sink)
        }
    }

    /// The settings the next quest will be generated with.
    var currentFingerprint: QuestSettingsFingerprint { QuestSettingsFingerprint(settings: settings) }


    var canRecheckWithStrongerModel: Bool {
        settings.offerStrongerRecheck && makeProvider().supportsStrongerRecheck && verdict?.recheckedWithStrongerModel != true
    }

    // MARK: Getting a quest

    func requestQuest() {
        guard !isBusy else { return }
        tracker.startNewQuest()
        Haptics.tap()
        run { try await self.generate() }
    }

    func reroll() {
        guard !isBusy, activeQuest != nil else { return }
        store.applyReroll()
        Haptics.tap()
        run { try await self.generate() }
    }

    func accept() {
        guard var quest = activeQuest else { return }
        quest.accepted = true
        quest.acceptedAt = Date()   // the time trial clock starts now
        activeQuest = quest
        phase = .active
        Haptics.success()
    }

    func abandon() {
        currentTask?.cancel()
        activeQuest = nil
        pendingPhotos = []
        capturedPhotos = []
        submittedAt = nil
        resetResult()
        phase = .idle
    }

    /// Throws the quest away entirely, so the player can change settings first.
    /// Costs the same as a reroll: discarding and asking again is a reroll by another name.
    func discard() {
        guard activeQuest != nil else { return }
        store.applyReroll()
        abandon()
        Haptics.tap()
    }

    func cancelWork() {
        currentTask?.cancel()
        phase = restingPhase
    }

    private func generate() async throws {
        let scope = settings.scope
        let provider = makeProvider()
        let fingerprint = currentFingerprint
        var context = QuestContext(scope: scope, theme: settings.theme, difficulty: settings.difficulty,
                                   money: settings.money, allowPeople: settings.allowPeople,
                                   mode: settings.mode, timeTrial: settings.timeTrial)
        context.recentQuestTitles = store.recentTitles() + (activeQuest.map { [$0.quest.title] } ?? [])
        var origin: CLLocation?
        var venueName: String?

        switch scope {
        case .venue:
            let description = settings.venueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else {
                throw FlowError.needsVenue
            }
            context.venueDescription = description
            if let cached = store.cachedVenue(description, provider: provider.kind) {
                context.venue = cached
            } else {
                phase = .working("Researching your venue (one-time)…")
                let venue = try await provider.research(venue: description)
                store.cacheVenue(venue, description: description, provider: provider.kind)
                context.venue = venue
            }
            venueName = context.venue?.venueName
        case .nearby, .city:
            phase = .working("Finding where you are…")
            let here = try await location.currentLocation()
            origin = here
            phase = .working(scope == .nearby ? "Scouting real places nearby…" : "Scouting the city…")
            let (places, areaName) = await places(around: here, scope: scope)
            context.places = places
            #if DEBUG
            if let sample = MarketingSeed.placeOverride(near: here.geoPoint) { context.places.insert(sample, at: 0) }
            #endif
            context.areaName = areaName
            // Photo challenges lean on the weather and light right now. Best effort: never blocks a quest.
            if settings.mode == .photo {
                phase = .working("Checking the light and weather…")
                context.weather = try? await WeatherService.fetch(at: here.geoPoint)
                #if DEBUG
                if let sample = MarketingSeed.weatherOverride { context.weather = sample }
                #endif
            }
        }

        phase = .working(settings.mode == .photo
            ? ["Framing a challenge…", "Checking the light…", "Picking a lens…"].randomElement()!
            : ["Consulting the quest oracle…", "Rolling the quest dice…", "Sharpening the quest quill…"].randomElement()!)
        let tracker = self.tracker
        let engine = QuestEngine(provider: provider, onRejected: { violations in
            await tracker.recordRejection(violations)
        })
        let result = try await engine.generate(context: context)
        lastAttempts = result.attempts

        var quest = result.quest
        quest.isPhotoChallenge = settings.mode == .photo
        var active = ActiveQuest(quest: quest, scope: scope, theme: settings.theme, money: settings.money)
        active.venueName = venueName
        active.fingerprint = fingerprint
        active.weather = context.weather
        var targetDistance: Double?
        if let origin {
            active.origin = origin.geoPoint
            let match = PlaceValidator.matches(result.quest.targetPlace, allowed: context.places.map(\.name))
            let place = context.places.first { $0.name == match }
            active.targetCoordinate = place?.coordinate
            active.radiusMeters = Geofence.radius(scope: scope, hasSpecificTarget: place != nil)
            targetDistance = place.map { Double($0.distanceMeters) }
        }
        if settings.timeTrial {
            // The countdown fits the quest: harder and further away means more time.
            active.timeLimitSeconds = TimeTrial.limit(difficulty: quest.difficulty, distanceMeters: targetDistance,
                                                      scope: scope, photoCount: quest.photoCount)
        }
        activeQuest = active
        resetResult()
        capturedPhotos = []
        submittedAt = nil
        phase = .offered
        Haptics.pop()
    }

    private func places(around here: CLLocation, scope: QuestScope) async -> ([Place], String?) {
        if let cache = placesCache, cache.scope == scope, cache.theme == settings.theme,
           cache.location.distance(from: here) < 150, -cache.date.timeIntervalSinceNow < 600 {
            return (cache.places, cache.areaName)
        }
        async let areaName = location.placeName(for: here)
        let places = await placesService.places(around: here, scope: scope, theme: settings.theme)
        let name = await areaName
        placesCache = (scope, settings.theme, here, Date(), places, name)
        return (places, name)
    }

    // MARK: Completing it

    /// A photo taken for the current quest, before anything is processed or sent.
    struct CapturedPhoto: Identifiable {
        let id = UUID()
        var image: UIImage
        var hash: UInt64
        var isTestPhoto: Bool
    }

    /// Photos taken so far for the current quest (quests can ask for 1-4, one per find).
    private(set) var capturedPhotos: [CapturedPhoto] = []
    /// When the first set of photos was submitted (time trial).
    private(set) var submittedAt: Date?

    /// Time trial: true if the photos went in before the deadline.
    var beatClock: Bool {
        guard let deadline = activeQuest?.deadline else { return false }
        return (submittedAt ?? Date()) <= deadline
    }

    var photosNeeded: Int { max(1, activeQuest?.quest.photoCount ?? 1) }

    /// Adds a photo to the set. Once the quest has all the photos it asked for, checking starts
    /// automatically; with fewer, the player can still tap "Check now".
    /// - Parameter testPhotoOutcome: set when a bundled debug test photo was used.
    func submitPhoto(_ image: UIImage, testPhotoOutcome: Verdict.Outcome? = nil) {
        guard activeQuest != nil, !isBusy else { return }
        notice = nil
        errorMessage = nil
        let isTestPhoto = testPhotoOutcome != nil
        if let testPhotoOutcome { lastTestOutcome = testPhotoOutcome }
        guard let hash = PerceptualHash.hash(image) else {
            errorMessage = FlowError.badPhoto.errorDescription
            return
        }
        // Reused photos don't count: not from earlier quests, and not twice in the same set.
        if !isTestPhoto || settings.checkDuplicatesForTestPhotos {
            if PerceptualHash.isNearDuplicate(hash, of: store.acceptedPhotoHashes()) {
                notice = "Looks like you've already used this photo for a quest. Snap a fresh one!"
                Haptics.warning()
                return
            }
            if PerceptualHash.isNearDuplicate(hash, of: capturedPhotos.map(\.hash)) {
                notice = "That's the same as a photo you already took for this quest. Find the next one!"
                Haptics.warning()
                return
            }
        }
        capturedPhotos.append(CapturedPhoto(image: image, hash: hash, isTestPhoto: isTestPhoto))
        Haptics.tap()
        if capturedPhotos.count >= photosNeeded { checkPhotos() }
    }

    func removeCapturedPhoto(_ id: UUID) {
        capturedPhotos.removeAll { $0.id == id }
    }

    /// Checks the photos taken so far (all of them, or fewer if the player couldn't find everything).
    func checkPhotos() {
        guard let active = activeQuest, !capturedPhotos.isEmpty, !isBusy else { return }
        // The clock stops when the photos are in, not when the AI finishes looking at them.
        if submittedAt == nil { submittedAt = Date() }
        let photos = capturedPhotos
        pendingPhotos = []
        run { try await self.prepareAndVerify(photos, active: active) }
    }

    private func prepareAndVerify(_ photos: [CapturedPhoto], active: ActiveQuest) async throws {
        // 1) Geofence at capture time (Nearby/City).
        if active.scope.usesLocation && !settings.skipGeofence, let center = active.geofenceCenter, let radius = active.radiusMeters {
            phase = .verifying("Checking you're in the right spot…")
            let here = try await location.currentLocation(maxAge: 10)
            switch Geofence.check(user: here.geoPoint, horizontalAccuracy: here.horizontalAccuracy, center: center, radius: radius) {
            case .inside:
                break
            case .outside(let distance, _):
                let target = active.quest.targetsAnyPlace ? "the quest area" : active.quest.targetPlace
                notice = "You're about \(Geofence.friendlyDistance(distance)) from \(target). Get a bit closer and snap again!"
                capturedPhotos = []
                phase = .active
                Haptics.warning()
                return
            case .tooInaccurate:
                notice = "Your location is a bit fuzzy right now. Step outside or wait a few seconds, then try again."
                phase = .active
                return
            }
        }

        // 2) Resize and blur faces on-device, before anything leaves the phone.
        phase = .verifying(photos.count == 1 ? "Blurring faces on your phone…" : "Blurring faces in your \(photos.count) photos…")
        var pending: [PendingPhoto] = []
        for photo in photos {
            let resized = ImageProcessor.redraw(photo.image, maxLongEdge: AIConfig.maxImageLongEdge)
            let redaction = await Task.detached(priority: .userInitiated) { FaceRedactor.redact(resized) }.value
            pending.append(PendingPhoto(resized: resized, redacted: redaction.image, detectedRegions: redaction.regions,
                                        faceCount: redaction.faceCount, personCount: redaction.personCount,
                                        detectionFailed: redaction.detectionFailed))
        }
        pendingPhotos = pending

        // 3) If people are in any shot (or we couldn't check), let the player review the blurred versions first.
        if pending.contains(where: { $0.faceCount > 0 || $0.personCount > 0 || $0.detectionFailed }) || active.quest.involvesPeople {
            phase = .reviewing
            return
        }
        try await sendForVerification(pending, active: active)
    }

    /// Adds a blur spot where the player tapped on photo `index` (normalised 0...1 coordinates).
    func addBlurSpot(at normalized: CGPoint, photo index: Int = 0) {
        guard pendingPhotos.indices.contains(index) else { return }
        var pending = pendingPhotos[index]
        let size = CGSize(width: pending.resized.size.width * pending.resized.scale,
                          height: pending.resized.size.height * pending.resized.scale)
        pending.extraRegions.append(FaceRedactor.spot(at: CGPoint(x: normalized.x * size.width, y: normalized.y * size.height), in: size))
        rerenderPending(pending, at: index)
    }

    func undoBlurSpot(photo index: Int = 0) {
        guard pendingPhotos.indices.contains(index), !pendingPhotos[index].extraRegions.isEmpty else { return }
        var pending = pendingPhotos[index]
        pending.extraRegions.removeLast()
        rerenderPending(pending, at: index)
    }

    private func rerenderPending(_ pending: PendingPhoto, at index: Int) {
        var updated = pending
        if let cg = pending.resized.cgImage {
            updated.redacted = UIImage(cgImage: FaceRedactor.redact(cg, regions: pending.detectedRegions + pending.extraRegions))
        }
        pendingPhotos[index] = updated
        Haptics.tap()
    }

    func confirmReviewedPhoto() {
        guard !pendingPhotos.isEmpty, let active = activeQuest, phase == .reviewing else { return }
        let pending = pendingPhotos
        run { try await self.sendForVerification(pending, active: active) }
    }

    func cancelReview() {
        pendingPhotos = []
        capturedPhotos = []
        phase = .active
    }

    private func sendForVerification(_ pending: [PendingPhoto], active: ActiveQuest) async throws {
        phase = .verifying(pending.count == 1 ? "Looking at your photo…" : "Looking at your \(pending.count) photos…")
        // Only the blurred, metadata-free versions are ever sent or kept.
        let jpegs = pending.compactMap { ImageProcessor.strippedJPEG($0.redacted, quality: AIConfig.jpegQuality) }
        guard jpegs.count == pending.count, !jpegs.isEmpty else { throw FlowError.badPhoto }
        photos = pending.map(\.redacted)
        photoHashes = capturedPhotos.map(\.hash)
        preparedJPEGs = jpegs
        pendingPhotos = []

        // 4) Lenient AI verification of the whole set.
        let provider = makeProvider(testPhotoOutcome: lastTestOutcome)
        let raw = try await provider.verify(photos: jpegs, criteria: active.quest.successCriteria, quest: active.quest, useStrongerModel: false)
        // A try only counts once the referee has actually looked (not on errors or cancels).
        if var counted = activeQuest {
            counted.checksUsed = (counted.checksUsed ?? 0) + 1
            activeQuest = counted
        }
        try await handle(VerdictPolicy.applyLeniency(raw))
    }

    private func handle(_ result: Verdict) async throws {
        verdict = result
        switch result.verdict {
        case .pass:
            complete(with: result)
        case .unsure:
            phase = .result
            Haptics.warning()
        case .fail:
            phase = .result
            Haptics.error()
        }
    }

    /// "Unsure" offers one optional retake; otherwise it passes.
    func acceptUnsure() {
        guard var result = verdict, result.verdict == .unsure else { return }
        result.verdict = .pass
        passedOnBenefitOfDoubt = true
        complete(with: result)
    }

    // MARK: Tries

    /// Free or bought photo checks left for this quest.
    var triesLeft: Int { activeQuest?.triesLeft ?? 0 }
    var nextTryPrice: Int { activeQuest?.nextTryPrice ?? 0 }
    var points: Int { store.profile().points }
    var canAffordAnotherTry: Bool { activeQuest != nil && points >= nextTryPrice }

    /// "Unsure" → take new photos, if a try is left ("Count it!" is always free).
    func retake() {
        guard triesLeft > 0 else { return }
        startAnotherTry()
    }

    /// "Not quite" → take new photos, if a try is left.
    func tryAnotherPhoto() {
        guard triesLeft > 0 else { return }
        startAnotherTry()
    }

    /// Out of tries: spend points on one more photo check. Each extra try costs more than the last.
    func buyAnotherTry() {
        guard var active = activeQuest, active.triesLeft == 0, outcome == nil, !isBusy else { return }
        guard store.spend(active.nextTryPrice) else {
            errorMessage = "You need \(active.nextTryPrice) points for another try and have \(points)."
            Haptics.warning()
            return
        }
        active.extraTriesBought = (active.extraTriesBought ?? 0) + 1
        activeQuest = active
        Haptics.tap()
        startAnotherTry()
    }

    private func startAnotherTry() {
        resetResult()
        capturedPhotos = []
        // The clock keeps running: what counts for the time trial is when the next photos go in.
        submittedAt = nil
        phase = .active
    }

    func recheckWithStrongerModel() {
        guard !preparedJPEGs.isEmpty, let active = activeQuest, !isBusy else { return }
        let jpegs = preparedJPEGs
        run {
            self.phase = .verifying("Asking a sharper-eyed referee…")
            let provider = self.makeProvider(testPhotoOutcome: self.lastTestOutcome)
            let raw = try await provider.verify(photos: jpegs, criteria: active.quest.successCriteria, quest: active.quest, useStrongerModel: true)
            var result = VerdictPolicy.applyLeniency(raw)
            result.recheckedWithStrongerModel = true
            try await self.handle(result)
        }
    }

    private func complete(with result: Verdict) {
        guard let active = activeQuest else { return }
        let thumbnail = photos.first.flatMap(ImageProcessor.thumbnail)
        outcome = store.complete(active, verdict: result, photoHashes: photoHashes, thumbnail: thumbnail,
                                 aiCalls: tracker.currentQuestCalls.count, aiCostUSD: tracker.currentQuestCost,
                                 beatClock: active.isTimeTrial && beatClock)
        verdict = result
        phase = .result
        Haptics.success()
    }

    /// Leave the result screen.
    func finish() {
        if outcome != nil { activeQuest = nil; submittedAt = nil }
        resetResult()
        photos = []
        capturedPhotos = []
        phase = activeQuest == nil ? .idle : .active
    }

    private func resetResult() {
        verdict = nil
        outcome = nil
        preparedJPEGs = []
        photoHashes = []
        passedOnBenefitOfDoubt = false
    }

    // MARK: Plumbing

    /// Where to land after an error or cancellation.
    private var restingPhase: Phase {
        guard let quest = activeQuest else { return .idle }
        if verdict != nil { return .result }
        if !pendingPhotos.isEmpty { return .reviewing }
        return quest.accepted ? .active : .offered
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        currentTask?.cancel()
        errorMessage = nil
        notice = nil
        currentTask = Task { @MainActor in
            do {
                try await work()
            } catch is CancellationError {
                self.phase = self.restingPhase
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
                self.phase = self.restingPhase
                Haptics.error()
            }
        }
    }

    private static let activeQuestKey = "flow.activeQuest"

    private func persistActiveQuest() {
        if let activeQuest, let data = try? JSONEncoder().encode(activeQuest) {
            defaults.set(data, forKey: Self.activeQuestKey)
        } else {
            defaults.removeObject(forKey: Self.activeQuestKey)
        }
    }

    private func restoreActiveQuest() {
        guard let data = defaults.data(forKey: Self.activeQuestKey),
              let saved = try? JSONDecoder().decode(ActiveQuest.self, from: data) else { return }
        activeQuest = saved
        phase = saved.accepted ? .active : .offered
    }
}

enum FlowError: LocalizedError {
    case needsVenue
    case badPhoto

    var errorDescription: String? {
        switch self {
        case .needsVenue: return "Tell me where you are first — tap the scope chip and type your venue in one line."
        case .badPhoto: return "Couldn't read that photo. Try snapping another."
        }
    }
}
