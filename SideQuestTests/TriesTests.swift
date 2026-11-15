import XCTest
import SwiftData
import UIKit
@testable import SideQuest

final class TriesPricingTests: XCTestCase {
    func testPriceScalesWithTheQuestAndDoubles() {
        XCTAssertEqual((1...4).map { Tries.price(forExtraTry: $0, award: 90) }, [10, 20, 40, 75])
        XCTAssertEqual((1...4).map { Tries.price(forExtraTry: $0, award: 250) }, [25, 50, 100, 200])
    }

    func testPriceAlwaysGoesUpEvenForTinyQuests() {
        for award in [0, 5, 30, 90, 250] {
            let prices = (1...12).map { Tries.price(forExtraTry: $0, award: award) }
            XCTAssertEqual(prices.first.map { $0 >= 5 }, true)
            for (a, b) in zip(prices, prices.dropFirst()) {
                XCTAssertGreaterThan(b, a, "award \(award): \(prices)")
            }
        }
        // Silly numbers don't overflow.
        XCTAssertGreaterThan(Tries.price(forExtraTry: 10_000, award: 250), 0)
    }

    func testActiveQuestCountsTries() {
        var active = ActiveQuest(quest: makeQuest(difficulty: 3, points: 30), scope: .venue, theme: nil, money: .default)
        XCTAssertEqual(active.triesLeft, Tries.free)
        active.checksUsed = 2
        XCTAssertEqual(active.triesLeft, 0)
        XCTAssertEqual(active.nextTryPrice, 10)   // 90-point quest
        active.extraTriesBought = 1
        XCTAssertEqual(active.triesLeft, 1)
        XCTAssertEqual(active.nextTryPrice, 20)
    }

    func testOldSavedQuestsStillLoad() throws {
        let active = ActiveQuest(quest: makeQuest(), scope: .venue, theme: nil, money: .default)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(active)) as? [String: Any])
        json.removeValue(forKey: "checksUsed")
        json.removeValue(forKey: "extraTriesBought")
        let decoded = try JSONDecoder().decode(ActiveQuest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.triesLeft, Tries.free)
    }
}

@MainActor
final class BuyAnotherTryFlowTests: XCTestCase {
    func makeFlow() throws -> (QuestFlowModel, ProgressStore) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.providerKind = .demo
        settings.scope = .venue
        settings.venueDescription = "Test Hack"
        settings.mode = .quest
        settings.difficulty = .easy
        let container = try ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ProgressStore(context: container.mainContext)
        let flow = QuestFlowModel(settings: settings, tracker: AIUsageTracker(defaults: defaults), location: LocationService(),
                                  store: store, defaults: defaults)
        return (flow, store)
    }

    /// Submits test photos for every find the quest asks for and waits for the verdict.
    func check(_ flow: QuestFlowModel, outcome: Verdict.Outcome) async throws {
        let count = flow.photosNeeded
        for i in 0..<count {
            flow.submitPhoto(Self.photo(i), testPhotoOutcome: outcome)
        }
        try await waitFor { flow.phase == .result || flow.phase == .reviewing }
        if flow.phase == .reviewing { flow.confirmReviewedPhoto() }
        try await waitFor { flow.phase == .result && !flow.isBusy }
    }

    func testTwoFreeTriesThenPricierPaidOnes() async throws {
        let (flow, store) = try makeFlow()
        store.profile().points = 100

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        flow.accept()
        XCTAssertEqual(flow.triesLeft, Tries.free)

        // Two free misses.
        try await check(flow, outcome: .fail)
        XCTAssertEqual(flow.verdict?.verdict, .fail)
        XCTAssertEqual(flow.triesLeft, 1)
        flow.tryAnotherPhoto()
        XCTAssertEqual(flow.phase, .active)
        try await check(flow, outcome: .fail)
        XCTAssertEqual(flow.triesLeft, 0)

        // No free tries: "try another photo" does nothing, buying one costs points.
        flow.tryAnotherPhoto()
        XCTAssertEqual(flow.phase, .result)
        let firstPrice = flow.nextTryPrice
        flow.buyAnotherTry()
        XCTAssertEqual(flow.phase, .active)
        XCTAssertEqual(store.profile().points, 100 - firstPrice)
        XCTAssertEqual(flow.triesLeft, 1)

        // The next one costs more.
        try await check(flow, outcome: .fail)
        let secondPrice = flow.nextTryPrice
        XCTAssertGreaterThan(secondPrice, firstPrice)
        flow.buyAnotherTry()
        XCTAssertEqual(store.profile().points, 100 - firstPrice - secondPrice)

        // A pass still pays the full award.
        let award = Scoring.award(points: try XCTUnwrap(flow.activeQuest).quest.points,
                                  difficulty: try XCTUnwrap(flow.activeQuest).quest.difficulty)
        try await check(flow, outcome: .pass)
        XCTAssertEqual(flow.outcome?.pointsAwarded, award)
        XCTAssertEqual(store.profile().points, 100 - firstPrice - secondPrice + award)
    }

    func testCantBuyWithoutEnoughPoints() async throws {
        let (flow, store) = try makeFlow()
        store.profile().points = 0

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        flow.accept()
        for _ in 0..<Tries.free {
            if flow.phase == .result { flow.tryAnotherPhoto() }
            try await check(flow, outcome: .fail)
        }
        XCTAssertEqual(flow.triesLeft, 0)
        XCTAssertFalse(flow.canAffordAnotherTry)
        flow.buyAnotherTry()
        XCTAssertEqual(flow.phase, .result, "Stays on the result screen")
        XCTAssertEqual(store.profile().points, 0, "Points never go negative")
        XCTAssertNotNil(flow.errorMessage)
    }

    func testUnsureRetakeUsesATryButCountItIsFree() async throws {
        let (flow, store) = try makeFlow()
        store.profile().points = 0

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        flow.accept()
        try await check(flow, outcome: .unsure)
        XCTAssertEqual(flow.verdict?.verdict, .unsure)
        flow.retake()
        XCTAssertEqual(flow.phase, .active)
        try await check(flow, outcome: .unsure)
        XCTAssertEqual(flow.triesLeft, 0)
        flow.retake()
        XCTAssertEqual(flow.phase, .result, "No tries left for a retake")
        flow.acceptUnsure()
        XCTAssertNotNil(flow.outcome)
    }

    // MARK: Helpers

    static func photo(_ i: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { ctx in
            UIColor(hue: CGFloat(i) / 5, saturation: 1, brightness: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.white.setFill(); ctx.fill(CGRect(x: CGFloat(i * 50), y: 20, width: 60, height: 120))
        }
    }

    private func waitFor(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
