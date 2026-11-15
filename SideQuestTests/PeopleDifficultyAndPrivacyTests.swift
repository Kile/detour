import XCTest
import SwiftData
@testable import SideQuest

final class PeopleModeTests: XCTestCase {
    let solo = SafetyValidator.Context(scope: .venue, isNightTime: false, allowPeople: false)
    let social = SafetyValidator.Context(scope: .venue, isNightTime: false, allowPeople: true)

    let monsterQuest = makeQuest(
        title: "Monster Census",
        description: "Find someone who has already had 5 Monster energy drinks today. Ask if they're up for a photo of their empty cans.",
        successCriteria: ["At least 5 empty Monster cans are visible", "A hand giving a thumbs up is next to the cans",
                          "The cans are grouped together"],
        photoInstructions: "Frame the cans and their hand. Faces get blurred automatically.",
        difficulty: 5, points: 50, involvesPeople: true)

    func testUsersMonsterExampleIsFineInPeopleMode() {
        XCTAssertEqual(SafetyValidator.validate(monsterQuest, context: social), [])
    }

    func testPeopleQuestsAreRejectedInSoloMode() {
        let violations = SafetyValidator.validate(monsterQuest, context: solo)
        XCTAssertTrue(violations.contains { $0.message.contains("people quests are turned off") }, "\(violations)")
    }

    func testSoloModeRejectsQuietInteractionToo() {
        for text in ["Ask a stranger for their favourite café.", "Find someone wearing a red hoodie.",
                     "Get three people to high five you.", "Chat with a fellow hacker about their project."] {
            XCTAssertFalse(SafetyValidator.validate(makeQuest(description: text), context: solo).isEmpty, text)
        }
    }

    func testPeopleModeNeedsPermissionBeforePhotos() {
        let rude = makeQuest(description: "Find someone who has had 5 Monsters and photograph their cans.",
                             successCriteria: ["At least 5 cans are visible", "The cans are empty", "They are on one table"],
                             difficulty: 4, involvesPeople: true)
        let violations = SafetyValidator.validate(rude, context: social)
        XCTAssertTrue(violations.contains { $0.message.contains("permission") }, "\(violations)")
    }

    func testProofCanNeverDependOnFacesOrIdentity() {
        for criterion in ["Their face is visible", "The person is smiling", "Their name badge is readable",
                          "You can identify who they are"] {
            let quest = makeQuest(description: "Ask a hacker to pose with their laptop.", successCriteria: [criterion, "A laptop is visible"],
                                  involvesPeople: true)
            XCTAssertTrue(SafetyValidator.validate(quest, context: social).contains { $0.message.contains("faces, names") },
                          criterion)
        }
        // Clock faces are fine.
        XCTAssertEqual(SafetyValidator.validate(makeQuest(successCriteria: ["The clock face is readable", "A clock is visible"]),
                                                context: solo), [])
    }

    func testChildrenAreAlwaysOffLimits() {
        let quest = makeQuest(description: "Ask a kid to show you their favourite toy, if their parent is okay with it.", involvesPeople: true)
        XCTAssertTrue(SafetyValidator.validate(quest, context: social).contains { $0.message.contains("children") })
    }

    func testEnergyDrinksAreAllowed() {
        let quest = makeQuest(description: "Find a table with at least 15 Monster energy drink cans on it.",
                              successCriteria: ["At least 15 cans are visible", "The cans are on one table", "The table fits in the frame"],
                              difficulty: 5)
        XCTAssertEqual(SafetyValidator.validate(quest, context: solo), [])
    }

    func testOldSavedQuestsWithoutPeopleFieldStillLoad() throws {
        let quest = try QuestJSON.decode(questJSON(removing: ["involves_people"]))
        XCTAssertFalse(quest.involvesPeople)
    }

    func testPromptExplainsPeopleModeAndProof() {
        let on = QuestPrompts.generationUser(makeContext(scope: .venue, venue: sampleVenue, allowPeople: true))
        XCTAssertTrue(on.contains("PEOPLE: ON"))
        XCTAssertTrue(on.contains("thumbs up"))
        let off = QuestPrompts.generationUser(makeContext(scope: .venue, venue: sampleVenue))
        XCTAssertTrue(off.contains("PEOPLE: OFF"))
        XCTAssertTrue(QuestPrompts.verificationSystem.contains("deliberately blurred"))
    }
}

final class DifficultyValidatorTests: XCTestCase {
    let hardQuest = makeQuest(description: "Find a table with at least 15 cans on it.",
                              successCriteria: ["At least 15 cans are visible", "The cans are on one table", "The whole table is in frame"],
                              difficulty: 5, points: 50)

    func testDifficultyMustMatchRequest() {
        XCTAssertTrue(DifficultyValidator.validate(makeQuest(difficulty: 2), requested: .hard).contains { $0.message.contains("asked for 4-5") })
        XCTAssertTrue(DifficultyValidator.validate(makeQuest(difficulty: 4), requested: .easy).contains { $0.message.contains("asked for 1-2") })
        XCTAssertEqual(DifficultyValidator.validate(makeQuest(difficulty: 2), requested: .any), [])
    }

    func testHardQuestsMustBeDemanding() {
        XCTAssertEqual(DifficultyValidator.validate(hardQuest, requested: .hard), [])
        let thin = makeQuest(successCriteria: ["A table is visible", "There are cans"], difficulty: 5)
        let messages = DifficultyValidator.validate(thin, requested: .hard).map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("at least 3 success criteria") })
        XCTAssertTrue(messages.contains { $0.contains("count or precise detail") })
    }

    func testPromptSpellsOutWhatHardMeans() {
        let prompt = QuestPrompts.generationUser(makeContext(difficulty: .hard))
        XCTAssertTrue(prompt.contains("HARD"))
        XCTAssertTrue(QuestPrompts.generationSystem.contains("at least 15 cans"))
    }
}

final class FaceRedactorTests: XCTestCase {
    func checkerboard(size: Int = 400) -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            for y in stride(from: 0, to: size, by: 8) {
                for x in stride(from: 0, to: size, by: 8) {
                    ((x / 8 + y / 8) % 2 == 0 ? UIColor.black : UIColor.white).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }.cgImage!
    }

    func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    func variance(_ values: [UInt8]) -> Double {
        let mean = values.reduce(0.0) { $0 + Double($1) } / Double(values.count)
        return values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
    }

    func testRegionIsSmearedAndTheRestIsUntouched() {
        let original = checkerboard()
        let region = CGRect(x: 100, y: 100, width: 200, height: 200)
        let redacted = FaceRedactor.redact(original, regions: [region])
        let before = pixels(original), after = pixels(redacted)
        func inside(_ data: [UInt8]) -> [UInt8] {
            (150..<250).flatMap { y in (150..<250).map { x in data[y * 400 + x] } }
        }
        // The checkerboard detail inside the region is gone…
        XCTAssertGreaterThan(variance(inside(before)), 10_000)
        XCTAssertLessThan(variance(inside(after)), 1_000)
        // …and pixels well outside it are unchanged.
        for (x, y) in [(10, 10), (390, 20), (20, 390), (380, 380), (50, 200)] {
            XCTAssertEqual(Int(after[y * 400 + x]), Int(before[y * 400 + x]), accuracy: 2, "(\(x),\(y))")
        }
    }

    func testTapSpotIsCentredAndClamped() {
        let spot = FaceRedactor.spot(at: CGPoint(x: 500, y: 500), in: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(spot.midX, 500, accuracy: 0.5)
        XCTAssertEqual(spot.width, 140, accuracy: 0.5)
        let edge = FaceRedactor.spot(at: CGPoint(x: 0, y: 0), in: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(edge.minX, 0)
    }

    func testCoordinateConversion() {
        let rect = FaceRedactor.pixelRect(fromNormalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: CGSize(width: 400, height: 200))
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 200, height: 50))
    }

    /// Vision finds faces in some emoji; if it does on this runtime, the redacted image must have none.
    func testDetectedFaceIsGoneAfterRedaction() throws {
        let candidates = ["🧑🏻‍🍳", "🧑🏻‍🏫", "👩🏼‍🔬", "👨🏻‍🎤", "🧑🏻‍💻", "🧑‍🎨", "👩🏻", "👨🏻", "🧑🏽", "👱🏻‍♀️", "👴🏻", "🧔🏻"]
        for emoji in candidates {
          for size in [240.0, 320.0, 420.0, 520.0] {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 800), format: format).image { ctx in
                UIColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
                (emoji as NSString).draw(at: CGPoint(x: 120, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: size)])
            }
            guard !FaceRedactor.detectFaces(in: image.cgImage!).isEmpty else { continue }
            let result = FaceRedactor.redact(image)
            XCTAssertGreaterThan(result.faceCount, 0)
            XCTAssertTrue(result.foundPeople)
            XCTAssertEqual(FaceRedactor.detectFaces(in: result.image.cgImage!).count, 0, "Face still detectable after blurring \(emoji)")
            print("Face redaction verified with \(emoji) at \(Int(size)) pt")
            return
          }
        }
        throw XCTSkip("Vision didn't detect any synthetic face on this runtime")
    }

    func testPhotoWithoutPeopleIsLeftAlone() throws {
        let image = try XCTUnwrap(UIImage(named: "debug_test_pass.jpg"))
        let result = FaceRedactor.redact(image)
        XCTAssertFalse(result.foundPeople)
        XCTAssertTrue(result.regions.isEmpty)
    }
}

final class GeminiClientTests: XCTestCase {
    var session: URLSession!
    var sleeps: [Double] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        sleeps = []
    }

    func client(key: String? = "AIzaTestKey_0123456789abcdefghijklmnop") -> GeminiClient {
        GeminiClient(apiKey: { key }, session: session, sleep: { [weak self] seconds in self?.sleeps.append(seconds) })
    }

    static func response(text: String, finish: String = "STOP", thought: Bool = true, grounding: String = "") -> Data {
        let textJSON = String(data: try! JSONSerialization.data(withJSONObject: ["text": text]), encoding: .utf8)!
        let parts = (thought ? [#"{"text":"thinking...","thought":true}"#] : []) + [textJSON]
        return Data("""
        {"candidates":[{"content":{"role":"model","parts":[\(parts.joined(separator: ","))]},"finishReason":"\(finish)"\(grounding)}],
         "usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":200,"thoughtsTokenCount":50,"totalTokenCount":1250}}
        """.utf8)
    }

    static func error(_ code: Int, _ status: String, _ message: String, details: String = "") -> Data {
        Data(#"{"error":{"code":\#(code),"message":"\#(message)","status":"\#(status)","details":[\#(details)]}}"#.utf8)
    }

    func body(_ index: Int = 0) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[index].body) as? [String: Any])
    }

    func testGeminiQuestRequestShapeAndParsing() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: Self.response(text: String(data: questJSON(), encoding: .utf8)!))]
        let provider = GeminiProvider(client: client(), model: .flashLite)
        let quest = try await provider.generateQuest(context: makeContext())
        XCTAssertEqual(quest.title, "Door Collector")

        let request = StubURLProtocol.requests[0].request
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIzaTestKey_0123456789abcdefghijklmnop")
        XCTAssertFalse(request.url!.absoluteString.contains("key="), "Key never goes in the URL")

        let json = try body()
        let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        XCTAssertNil(config["temperature"])
        XCTAssertEqual((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "minimal")
        let schema = try XCTUnwrap(config["responseJsonSchema"] as? [String: Any])
        let difficulty = try XCTUnwrap((schema["properties"] as? [String: Any])?["difficulty"] as? [String: Any])
        XCTAssertNil(difficulty["enum"], "Integer enums are stripped for Gemini")
        XCTAssertNotNil(json["systemInstruction"])
        let bodyText = String(data: StubURLProtocol.requests[0].body, encoding: .utf8)!
        XCTAssertFalse(bodyText.contains("51.519"), "Coordinates are never sent")
    }

    func testGemmaGetsSchemaInThePromptInstead() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: Self.response(text: "```json\n" + String(data: questJSON(), encoding: .utf8)! + "\n```"))]
        _ = try await GeminiProvider(client: client(), model: .gemma31b).generateQuest(context: makeContext())
        let json = try body()
        let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertNil(config["responseJsonSchema"])
        XCTAssertNil(config["responseMimeType"])
        let system = String(data: try JSONSerialization.data(withJSONObject: json["systemInstruction"]!), encoding: .utf8)!
        XCTAssertTrue(system.contains("involves_people"), "Schema is spelled out in the system prompt")
        XCTAssertEqual(StubURLProtocol.requests[0].request.url?.lastPathComponent, "gemma-4-31b-it:generateContent")
    }

    func testVerifySendsImageAndUsesStrongerModelForRecheck() async throws {
        let verdict = #"{"verdict":"pass","criteria":[{"criterion":"A vase","met":true,"reason":"Visible"}],"confidence":0.9,"feedback":"Nice!"}"#
        StubURLProtocol.replies = [.init(status: 200, body: Self.response(text: verdict))]
        let result = try await GeminiProvider(client: client(), model: .gemma26b)
            .verify(photos: [Data([0xFF, 0xD8])], criteria: ["A vase"], quest: makeQuest(), useStrongerModel: true)
        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(result.recheckedWithStrongerModel, true)
        XCTAssertEqual(StubURLProtocol.requests[0].request.url?.lastPathComponent, "gemini-3.8-flash:generateContent")
        let parts = try XCTUnwrap(((try body()["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        let inline = try XCTUnwrap(parts.first?["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(inline["data"] as? String, "/9g=")
    }

    func testThoughtPartsAreIgnored() throws {
        let response = try JSONDecoder().decode(GeminiResponse.self, from: Self.response(text: "{}"))
        XCTAssertEqual(response.text, "{}")
        XCTAssertEqual(response.inputTokens, 1000)
        XCTAssertEqual(response.outputTokens, 250, "Thinking tokens are billed as output")
    }

    func testRateLimitRetriesThenCoolsDown() async {
        let retryInfo = #"{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"31s"}"#
        StubURLProtocol.replies = [
            .init(status: 429, body: Self.error(429, "RESOURCE_EXHAUSTED", "Quota exceeded", details: retryInfo)),
            .init(status: 429, body: Self.error(429, "RESOURCE_EXHAUSTED", "Quota exceeded", details: retryInfo)),
        ]
        do {
            _ = try await GeminiProvider(client: client()).generateQuest(context: makeContext())
            XCTFail("Expected cooling down")
        } catch {
            XCTAssertEqual(error as? AIError, .coolingDown(seconds: 31))
            XCTAssertTrue((error as? AIError)?.errorDescription?.contains("cooling down") ?? false)
        }
        XCTAssertEqual(sleeps, [AIConfig.maxRetryAfterSeconds], "Waits are capped")
    }

    func testErrorMapping() {
        let invalid = GeminiClient.parseError(Self.error(400, "INVALID_ARGUMENT", "API key not valid. Please pass a valid API key.",
                                                         details: #"{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}"#))
        XCTAssertEqual(GeminiClient.map(status: 400, error: invalid, model: nil), .invalidAPIKey)
        XCTAssertEqual(GeminiClient.map(status: 401, error: .init(), model: nil), .invalidAPIKey)
        XCTAssertEqual(GeminiClient.map(status: 403, error: .init(message: "Your API key was reported as leaked."), model: nil), .invalidAPIKey)
        XCTAssertEqual(GeminiClient.map(status: 503, error: .init(), model: nil), .overloaded)
        XCTAssertEqual(GeminiClient.map(status: 404, error: .init(), model: "gemma-4-31b-it"), .modelUnavailable("gemma-4-31b-it"))
        XCTAssertEqual(GeminiClient.map(status: 400, error: .init(message: "google_search tool is not supported for this model"), model: nil),
                       .webSearchUnavailable)
    }

    func testBlockedAndTruncatedResponses() async {
        StubURLProtocol.replies = [.init(status: 200, body: Self.response(text: "", finish: "SAFETY"))]
        do { _ = try await GeminiProvider(client: client()).generateQuest(context: makeContext()); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .refused) }
        StubURLProtocol.replies = [.init(status: 200, body: Self.response(text: "{", finish: "MAX_TOKENS"))]
        do { _ = try await GeminiProvider(client: client()).generateQuest(context: makeContext()); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .truncated) }
    }

    func testResearchUsesGoogleSearchAndFallsBackWithoutIt() async throws {
        let venueJSON = #"{"venue_name":"Test Venue","summary":"A venue.","areas":[{"name":"Great Hall","description":"Big."}],"typical_things":[],"events_and_highlights":[],"sponsors":[],"rules_and_etiquette":[]}"#
        let grounding = #","groundingMetadata":{"webSearchQueries":["test venue rooms"],"groundingChunks":[{"web":{"uri":"https://example.com/venue","title":"Venue"}}]}"#
        StubURLProtocol.replies = [
            .init(status: 200, body: Self.response(text: "It has a Great Hall.", grounding: grounding)),
            .init(status: 200, body: Self.response(text: venueJSON)),
        ]
        let venue = try await GeminiProvider(client: client()).research(venue: "Test Venue")
        XCTAssertEqual(venue.sources, ["https://example.com/venue"])
        XCTAssertEqual(venue.usedWebSearch, true)
        XCTAssertNotNil(try body(0)["tools"])
        XCTAssertNil(try body(1)["tools"])

        // Free-tier keys can't use Search: research still works from the model's own knowledge.
        StubURLProtocol.reset()
        StubURLProtocol.replies = [
            .init(status: 400, body: Self.error(400, "INVALID_ARGUMENT", "Search grounding is not available on the free tier")),
            .init(status: 200, body: Self.response(text: "Notes from memory.")),
            .init(status: 200, body: Self.response(text: venueJSON)),
        ]
        let fallback = try await GeminiProvider(client: client()).research(venue: "Test Venue")
        XCTAssertEqual(fallback.usedWebSearch, false)
        XCTAssertNil(try body(1)["tools"])
    }

    func testGeminiKeyStorageIsSeparateFromClaude() throws {
        XCTAssertNotEqual(APIKeyStore.account(for: .claude), APIKeyStore.account(for: .gemini))
        XCTAssertNil(APIKeyStore.account(for: .demo))
        XCTAssertTrue(APIKeyStore.looksValid("AIzaSyA1234567890abcdefghijklmnopqrstu", for: .gemini))
        XCTAssertFalse(APIKeyStore.looksValid("short", for: .gemini))
    }
}

@MainActor
final class DiscardAndRerollTests: XCTestCase {
    func makeFlow() throws -> (QuestFlowModel, AppSettings, ProgressStore) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.providerKind = .demo
        let container = try ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ProgressStore(context: container.mainContext)
        let flow = QuestFlowModel(settings: settings, tracker: AIUsageTracker(defaults: defaults), location: LocationService(),
                                  store: store, defaults: defaults)
        return (flow, settings, store)
    }

    func testFingerprintReportsWhatChanged() {
        let base = QuestSettingsFingerprint(scope: .venue, venue: "Hack", theme: nil, difficulty: .any, allowPeople: false, money: .default)
        var changed = base
        changed.difficulty = .hard
        changed.allowPeople = true
        XCTAssertEqual(changed.changes(since: base), ["Hard", "People on"])
        XCTAssertEqual(base.changes(since: base), [])
        XCTAssertTrue(changed.labels.contains("👥 People"))
    }

    func testDiscardCostsTheSameAsAReroll() async throws {
        let (flow, settings, store) = try makeFlow()
        settings.scope = .venue
        settings.venueDescription = "Test Hack"
        store.profile().points = 100

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        XCTAssertNotNil(flow.activeQuest?.fingerprint)

        flow.discard()
        XCTAssertNil(flow.activeQuest)
        XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(store.profile().points, 100 - Scoring.rerollCost)

        // A new quest after discarding costs nothing extra, and uses the new settings.
        settings.difficulty = .hard
        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        XCTAssertEqual(store.profile().points, 100 - Scoring.rerollCost)
        XCTAssertGreaterThanOrEqual(flow.activeQuest?.quest.difficulty ?? 0, 4)
    }

    private func waitFor(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
