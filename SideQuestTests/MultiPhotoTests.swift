import XCTest
import SwiftData
@testable import SideQuest

final class ProofRulesTests: XCTestCase {
    func testEmptyFrameDemandsAreRejected() {
        for text in ["No people in the shot.", "Make sure nobody is in the frame.", "Keep people out of the shot.",
                     "Photograph it without any people."] {
            let violations = ProofRulesValidator.validate(makeQuest(photoInstructions: text))
            XCTAssertTrue(violations.contains { $0.rule == .proof }, text)
        }
        let criterion = makeQuest(successCriteria: ["A door is visible", "No people are visible"])
        XCTAssertFalse(ProofRulesValidator.validate(criterion).isEmpty)
        XCTAssertEqual(ProofRulesValidator.validate(makeQuest()), [])
    }

    func testMultiPhotoQuestsMustNotDemandOneFrame() {
        let crammed = makeQuest(description: "Find three logos.", successCriteria: ["3 logos are in a single photo", "Each is readable"],
                                photoCount: 3)
        XCTAssertTrue(ProofRulesValidator.validate(crammed).contains { $0.message.contains("one photo per find") })
        let fine = makeQuest(description: "Find three logos and capture each in a photo.",
                             successCriteria: ["3 different logos appear across the photos", "Each is readable"], photoCount: 3)
        XCTAssertEqual(ProofRulesValidator.validate(fine), [])
        // One photo of things that are naturally together is fine.
        let together = makeQuest(successCriteria: ["At least 15 cans are on one table", "The whole table fits in a single photo"])
        XCTAssertEqual(ProofRulesValidator.validate(together), [])
    }

    func testPhotoCountRangeAndDecoding() throws {
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["photo_count": 7])))
        XCTAssertEqual(try QuestJSON.decode(questJSON(["photo_count": 3])).photoCount, 3)
        XCTAssertEqual(try QuestJSON.decode(questJSON(removing: ["photo_count"])).photoCount, 1, "Older quests default to 1 photo")
    }

    func testPromptsTalkAboutOnePhotoPerFind() {
        XCTAssertTrue(QuestPrompts.generationSystem.contains("one photo per thing"))
        XCTAssertTrue(QuestPrompts.generationSystem.contains("Never require an empty frame"))
        XCTAssertTrue(QuestPrompts.verificationUser(quest: makeQuest(), criteria: ["a"], photoCount: 3).contains("3 attached photos"))
    }
}

final class MultiPhotoProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    let verdictJSON = #"{"verdict":"pass","criteria":[{"criterion":"3 logos","met":true,"reason":"One per photo"}],"confidence":0.9,"feedback":"Nice!"}"#

    func testClaudeSendsEveryPhotoLabelled() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: AnthropicClientTests.messageResponse(text: verdictJSON))]
        let client = AnthropicClient(apiKey: { "sk-ant-test-key-1234567890" }, session: session(), sleep: { _ in })
        _ = try await ClaudeProvider(client: client)
            .verify(photos: [Data([1]), Data([2]), Data([3])], criteria: ["3 logos"], quest: makeQuest(photoCount: 3), useStrongerModel: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].body) as? [String: Any])
        let content = try XCTUnwrap(((json["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(content.filter { $0["type"] as? String == "image" }.count, 3)
        XCTAssertEqual(content.first?["text"] as? String, "Photo 1 of 3:")
        XCTAssertTrue((content.last?["text"] as? String ?? "").contains("3 attached photos"))
    }

    func testGeminiSendsEveryPhotoLabelled() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: GeminiClientTests.response(text: verdictJSON))]
        let client = GeminiClient(apiKey: { "AIzaTestKey_0123456789abcdefghijklmnop" }, session: session(), sleep: { _ in })
        _ = try await GeminiProvider(client: client)
            .verify(photos: [Data([1]), Data([2])], criteria: ["3 logos"], quest: makeQuest(photoCount: 2), useStrongerModel: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].body) as? [String: Any])
        let parts = try XCTUnwrap(((json["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        XCTAssertEqual(parts.filter { $0["inlineData"] != nil }.count, 2)
        XCTAssertEqual(parts.first?["text"] as? String, "Photo 1 of 2:")
    }
}

@MainActor
final class MultiPhotoFlowTests: XCTestCase {
    func image(_ seed: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            let colors: [UIColor] = [.red, .blue, .green, .orange, .purple, .black]
            for i in 0..<4 {
                colors[(seed + i) % colors.count].setFill()
                ctx.fill(CGRect(x: CGFloat((seed * 37 + i * 90) % 320), y: CGFloat((seed * 53 + i * 70) % 220), width: 80, height: 80))
            }
        }
    }

    func testThreePhotoQuestCollectsThenChecksAllPhotos() async throws {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.providerKind = .demo
        settings.scope = .venue
        settings.venueDescription = "Test Hack"
        settings.difficulty = .hard
        let container = try ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ProgressStore(context: container.mainContext)
        let flow = QuestFlowModel(settings: settings, tracker: AIUsageTracker(defaults: defaults), location: LocationService(),
                                  store: store, defaults: defaults)

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        for _ in 0..<25 where (flow.activeQuest?.quest.photoCount ?? 1) < 2 {
            let previous = flow.activeQuest?.id
            flow.reroll()
            try await waitFor { flow.phase == .offered && flow.activeQuest?.id != previous }
        }
        let needed = try XCTUnwrap(flow.activeQuest?.quest.photoCount)
        guard needed > 1 else { return XCTFail("Expected a multi-photo demo quest (e.g. Sponsor Bingo)") }
        flow.accept()

        flow.submitPhoto(image(1))
        XCTAssertEqual(flow.capturedPhotos.count, 1)
        XCTAssertEqual(flow.phase, .active, "Waits for the remaining photos")

        flow.submitPhoto(image(1))   // the same photo again doesn't count
        XCTAssertEqual(flow.capturedPhotos.count, 1)
        XCTAssertNotNil(flow.notice)

        for seed in 2...needed { flow.submitPhoto(image(seed * 7)) }
        try await waitFor { flow.phase == .result || flow.phase == .reviewing }
        if flow.phase == .reviewing { flow.confirmReviewedPhoto() }
        try await waitFor { flow.outcome != nil }
        XCTAssertEqual(flow.photos.count, needed)
        let record = try XCTUnwrap(store.records().first)
        XCTAssertEqual(record.allHashes.count, needed, "Every photo's hash is kept to block reuse")
    }

    private func waitFor(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

final class ColourWordsTests: XCTestCase {
    func testYellowIsNotShouting() {
        let quest = makeQuest(description: "Find a yellow door.", successCriteria: ["A yellow door is visible", "It is a front door"])
        XCTAssertEqual(SafetyValidator.validate(quest, context: .init(scope: .nearby, isNightTime: false)), [])
        XCTAssertFalse(SafetyValidator.validate(makeQuest(description: "Yell your team name in the hall."),
                                                context: .init(scope: .venue, isNightTime: false)).isEmpty)
    }
}
