import SwiftUI
import MapKit

struct QuestCardView: View {
    @Environment(QuestFlowModel.self) private var flow
    @Environment(AppSettings.self) private var settings
    var active: ActiveQuest

    @State private var showCamera = false
    @State private var showTestPhotos = false
    @State private var showCameraUnavailable = false
    @State private var confirmAbandon = false
    @State private var showSettings = false

    private var quest: Quest { active.quest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if quest.involvesPeople {
                    noticeBanner("This quest involves other people. Ask before you photograph anyone or their things — faces are blurred on your phone before the photo is checked.",
                                 symbol: "person.2.fill", tint: .purple)
                }
                if active.scope.usesLocation, let center = active.geofenceCenter {
                    QuestMap(center: center, target: active.targetCoordinate, targetName: quest.targetPlace,
                             radius: active.radiusMeters ?? 300)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            if let target = active.targetCoordinate {
                                OpenInMapsMenu(target: target, name: quest.targetPlace, origin: active.origin)
                                    .padding(10)
                            }
                        }
                }
                infoSection(quest.photoCount > 1 ? "\(quest.photoCount) photos, one per find" : "Photo", symbol: "camera.fill") {
                    Text(quest.photoInstructions)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(quest.successCriteria, id: \.self) { criterion in
                            Label(criterion, systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                if active.money.enabled {
                    infoSection("Free path", symbol: "gift.fill") {
                        Text(quest.freePath)
                        if quest.hasOptionalPurchase {
                            Text("Optional spend: up to about £\(String(format: "%.2f", quest.optionalCostEstimate)). Totally optional — the free path earns exactly the same points.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !quest.safetyNotes.isEmpty {
                    infoSection("Stay safe", symbol: "hand.raised.fill") { Text(quest.safetyNotes) }
                }
                if let notice = flow.notice {
                    noticeBanner(notice, symbol: "location.circle.fill", tint: Theme.unsure)
                }
                if let error = flow.errorMessage {
                    ErrorBanner(message: error) { flow.errorMessage = nil }
                }
                AICostBadge().frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Theme.softGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .overlay { busyOverlay }
        .navigationTitle(quest.isPhotoChallenge
            ? (active.accepted ? "Your photo challenge" : "A challenge appears!")
            : (active.accepted ? "Your quest" : "A quest appears!"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if active.accepted {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Discard this quest", systemImage: "trash", role: .destructive) { confirmAbandon = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog("Discard this quest?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { flow.discard() }
        } message: { Text("Costs \(Scoring.rerollCost) points, the same as a reroll.") }
        .sheet(isPresented: $showSettings) {
            ScopeSheet().presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { flow.submitPhoto(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showTestPhotos) {
            TestPhotoPicker { image, outcome in
                showTestPhotos = false
                flow.submitPhoto(image, testPhotoOutcome: outcome)
            }
            .presentationDetents([.medium])
        }
        .alert("Camera not available", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(AppBrand.name) needs a camera to complete quests — photos from your library aren't accepted.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                WrappingHStack(spacing: 6) {
                    if quest.isPhotoChallenge { Pill(text: "Photo challenge", symbol: "camera.aperture", tint: Theme.asphalt) }
                    Pill(text: active.scope.title, symbol: active.scope.symbol)
                    if let theme = active.theme { Pill(text: "\(theme.emoji) \(theme.title)", tint: .purple) }
                    if quest.involvesPeople { Pill(text: "People", symbol: "person.2.fill", tint: .indigo) }
                    if let weather = active.weather { Pill(text: weather.label, tint: .blue) }
                }
                Spacer(minLength: 4)
                DifficultyStars(difficulty: quest.difficulty)
            }
            if active.isTimeTrial && !active.accepted { TimeTrialBanner(active: active) }
            Text(quest.title)
                .font(.largeTitle.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(quest.description)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Label("\(Scoring.award(points: quest.points, difficulty: quest.difficulty)) pts", systemImage: "star.circle.fill")
                    .foregroundStyle(Theme.gold)
                // In a time trial the countdown replaces the AI's rough estimate.
                if !active.isTimeTrial { Label("~\(quest.estimatedTimeMinutes) min", systemImage: "timer") }
                if !quest.targetsAnyPlace {
                    Label(quest.targetPlace, systemImage: "mappin.and.ellipse").lineLimit(1)
                } else if let venue = active.venueName {
                    Label(venue, systemImage: "building.2").lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private func infoSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func noticeBanner(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var actionBar: some View {
        VStack(spacing: 10) {
            if active.accepted {
                if active.isTimeTrial { TimeTrialBanner(active: active, compact: true) }
                if !flow.capturedPhotos.isEmpty { PhotoTray() }
                Button { takePhoto() } label: {
                    Label(takePhotoTitle, systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("takePhoto")
                if !flow.capturedPhotos.isEmpty && flow.capturedPhotos.count < flow.photosNeeded {
                    Button { flow.checkPhotos() } label: {
                        Text("Check now with \(flow.capturedPhotos.count) of \(flow.photosNeeded)")
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("checkNow")
                }
                if (active.checksUsed ?? 0) > 0 {
                    Text(active.triesLeft == 1 ? "Last try — make it count!" : "\(active.triesLeft) tries left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("triesLeft")
                }
            } else {
                NextQuestSettingsStrip(active: active) { showSettings = true }
                Button { flow.accept() } label: {
                    Label("Accept quest", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("acceptQuest")
                HStack(spacing: 10) {
                    Button { flow.reroll() } label: {
                        Label(rerollUsesNewSettings ? "Reroll · new settings" : "Reroll −\(Scoring.rerollCost)", systemImage: "dice.fill")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("rerollQuest")
                    .accessibilityHint("Costs \(Scoring.rerollCost) points and uses the settings shown above")
                    Button { flow.discard() } label: {
                        Label("Discard −\(Scoring.rerollCost)", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 140)
                    .accessibilityIdentifier("discardQuest")
                    .accessibilityHint("Costs \(Scoring.rerollCost) points. Throws this quest away so you can change settings first")
                }
            }
        }
        .bottomBar()
        .disabled(flow.isBusy)
    }

    @ViewBuilder private var busyOverlay: some View {
        if flow.isBusy {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text(flow.workingStatus ?? "Working…").font(.headline)
                    Button("Cancel") { flow.cancelWork() }.buttonStyle(.bordered)
                }
                .padding(30)
            }
            .transition(.opacity)
        }
    }

    private var takePhotoTitle: String {
        let needed = flow.photosNeeded
        guard needed > 1 else { return "Take photo" }
        return "Take photo \(min(flow.capturedPhotos.count + 1, needed)) of \(needed)"
    }

    private var rerollUsesNewSettings: Bool {
        guard let old = active.fingerprint else { return false }
        return !flow.currentFingerprint.changes(since: old).isEmpty
    }

    private func takePhoto() {
        flow.notice = nil
        let cameraAvailable = CameraPicker.isAvailable
        #if DEBUG
        if cameraAvailable && !settings.preferTestPhotos { showCamera = true } else { showTestPhotos = true }
        #else
        if cameraAvailable { showCamera = true } else { showCameraUnavailable = true }
        #endif
    }
}

/// Map of the quest target and the area the photo must be taken in.
private struct QuestMap: View {
    var center: GeoPoint
    var target: GeoPoint?
    var targetName: String
    var radius: Double

    var body: some View {
        let centre = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        let span = min(max(radius * 2.6, 600), 40_000)
        Map(initialPosition: .region(MKCoordinateRegion(center: centre, latitudinalMeters: span, longitudinalMeters: span))) {
            MapCircle(center: centre, radius: radius)
                .foregroundStyle(Theme.accent.opacity(0.12))
                .stroke(Theme.accent.opacity(0.6), lineWidth: 2)
            if let target {
                Marker(targetName, image: AppBrand.glyph,
                       coordinate: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude))
                    .tint(Theme.accent)
            }
            UserAnnotation()
        }
        .mapControls { MapUserLocationButton() }
        .accessibilityLabel(target == nil ? "Map of the quest area" : "Map showing \(targetName)")
    }
}

/// "Open in Maps" → pick Apple Maps or Google Maps for directions to the quest's place.
private struct OpenInMapsMenu: View {
    var target: GeoPoint
    var name: String
    var origin: GeoPoint?

    var body: some View {
        Menu {
            ForEach(MapsApp.allCases) { app in
                Button(app.title, systemImage: app == .apple ? "map" : "globe") {
                    MapsLauncher.open(app, target: target, name: name, origin: origin)
                }
            }
        } label: {
            Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .foregroundStyle(Theme.accent)
        }
        .accessibilityIdentifier("openInMaps")
        .accessibilityHint("Directions to \(name) in Apple Maps or Google Maps")
    }
}

/// Shows the settings the next reroll will use, highlights anything changed since this quest was
/// made, and opens the quick picks.
private struct NextQuestSettingsStrip: View {
    @Environment(QuestFlowModel.self) private var flow
    var active: ActiveQuest
    var change: () -> Void

    var body: some View {
        let current = flow.currentFingerprint
        let changed = active.fingerprint.map { current.changes(since: $0) } ?? []
        Button(action: change) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(changed.isEmpty ? "Next reroll uses" : "Next reroll uses NEW settings")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(changed.isEmpty ? Color.secondary : Theme.accent)
                    Text(current.labels.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !changed.isEmpty {
                        Text("Changed: " + changed.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("Change")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(changed.isEmpty ? Color.secondary.opacity(0.25) : Theme.accent, lineWidth: changed.isEmpty ? 1 : 2)
            }
            .animation(.spring(response: 0.3), value: changed)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nextQuestSettings")
        .accessibilityLabel("Next reroll uses \(current.labels.joined(separator: ", "))\(changed.isEmpty ? "" : ". Changed: " + changed.joined(separator: ", ")). Double-tap to change.")
    }
}

/// Thumbnails of the photos taken so far for a multi-photo quest, each removable.
private struct PhotoTray: View {
    @Environment(QuestFlowModel.self) private var flow

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(flow.capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { flow.removeCapturedPhoto(photo.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.asphalt)
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove photo \(index + 1)")
                    }
            }
            ForEach(flow.capturedPhotos.count..<max(flow.photosNeeded, flow.capturedPhotos.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "camera").foregroundStyle(Theme.accent.opacity(0.6)))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(flow.capturedPhotos.count) of \(flow.photosNeeded) photos taken")
    }
}

/// Time trial countdown. Before accepting it shows how long you'll get; after, it ticks down live.
private struct TimeTrialBanner: View {
    @Environment(QuestFlowModel.self) private var flow
    var active: ActiveQuest
    var compact = false

    var body: some View {
        if let limit = active.timeLimitSeconds {
            if let deadline = active.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let now = flow.submittedAt ?? timeline.date
                    let remaining = deadline.timeIntervalSince(now)
                    let tint = remaining <= 0 ? Theme.fail : (remaining < 60 ? Theme.unsure : Theme.accent)
                    HStack(spacing: 8) {
                        Image(systemName: remaining <= 0 ? "stopwatch" : "stopwatch.fill")
                        if flow.submittedAt != nil {
                            Text(remaining > 0 ? "Photos in with \(TimeTrial.format(remaining)) to spare" : "Photos in after the buzzer")
                        } else if remaining > 0 {
                            Text(TimeTrial.format(remaining)).monospacedDigit().fontWeight(.heavy)
                            Text(compact ? "left · +50% if you beat it" : "left to beat the clock (+50% points)")
                        } else {
                            Text("Time's up: finish for normal points")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            } else {
                Label("Time trial: you'll get \(Int(limit / 60)) min once you accept (+50% if you beat it)", systemImage: "stopwatch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
