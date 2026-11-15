import XCTest
@testable import SideQuest

/// Scripted provider: returns (or throws) the queued results in order and records contexts.
final class ScriptedProvider: AIProvider, @unchecked Sendable {
    enum Step { case quest(Quest), error(Error) }

    var steps: [Step]
    private(set) var contexts: [QuestContext] = []
    var kind: ProviderKind { .demo }
    var supportsStrongerRecheck: Bool { false }

    init(_ steps: [Step]) { self.steps = steps }

    func research(venue: String) async throws -> VenueContext { sampleVenue }

    func generateQuest(context: QuestContext) async throws -> Quest {
        contexts.append(context)
        guard !steps.isEmpty else { throw AIError.invalidResponse("script ran out") }
        switch steps.removeFirst() {
        case .quest(let quest): return quest
        case .error(let error): throw error
        }
    }

    func verify(photos: [Data], criteria: [String], quest: Quest, useStrongerModel: Bool) async throws -> Verdict {
        MockAIProvider.cannedVerdict(.pass, criteria: criteria)
    }
}

final class QuestEngineTests: XCTestCase {
    func testValidQuestOnFirstAttempt() async throws {
        let provider = ScriptedProvider([.quest(makeQuest())])
        let result = try await QuestEngine(provider: provider).generate(context: makeContext())
        XCTAssertEqual(result.attempts, 1)
        XCTAssertEqual(provider.contexts.count, 1)
    }

    func testInvalidQuestIsRegeneratedWithFeedback() async throws {
        let bad = makeQuest(description: "Buy a coffee.", requiresPurchase: true)
        let provider = ScriptedProvider([.quest(bad), .quest(makeQuest())])
        let result = try await QuestEngine(provider: provider).generate(context: makeContext())
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.rejected.count, 1)
        // The second request carries the reasons the first was rejected.
        XCTAssertTrue(provider.contexts[0].rejectionFeedback.isEmpty)
        XCTAssertTrue(provider.contexts[1].rejectionFeedback.contains { $0.contains("requires_purchase") })
    }

    func testGivesUpAfterTwoRetries() async {
        let bad = makeQuest(targetPlace: "Invented Emporium")
        let provider = ScriptedProvider([.quest(bad), .quest(bad), .quest(bad), .quest(makeQuest())])
        do {
            _ = try await QuestEngine(provider: provider).generate(context: makeContext())
            XCTFail("Expected an error")
        } catch let error as QuestEngineError {
            XCTAssertEqual(provider.contexts.count, 3)  // 1 attempt + 2 retries
            XCTAssertNotNil(error.errorDescription)
            if case .noValidQuest(let last) = error { XCTAssertTrue(last.contains { $0.contains("Invented Emporium") }) }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testMalformedJSONCountsAsAnAttempt() async throws {
        let provider = ScriptedProvider([.error(AIJSONError.notJSON), .quest(makeQuest())])
        let result = try await QuestEngine(provider: provider).generate(context: makeContext())
        XCTAssertEqual(result.attempts, 2)
    }

    func testNetworkErrorsAreNotRetriedHere() async {
        let provider = ScriptedProvider([.error(AIError.invalidAPIKey), .quest(makeQuest())])
        do {
            _ = try await QuestEngine(provider: provider).generate(context: makeContext())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AIError, .invalidAPIKey)
            XCTAssertEqual(provider.contexts.count, 1)
        }
    }

    func testDemoInvalidInjectionIsCaughtAndFixed() async throws {
        let mock = MockAIProvider(injectInvalidFirstQuest: true, latencySeconds: 0)
        var rejected: [[QuestViolation]] = []
        let result = try await QuestEngine(provider: mock).generate(context: makeContext())
        rejected = result.rejected
        XCTAssertEqual(result.attempts, 2)
        let rules = Set(rejected.first?.map(\.rule) ?? [])
        XCTAssertTrue(rules.contains(.money))
    }
}

/// Every canned demo quest must pass the same validators as real AI output.
final class MockCatalogTests: XCTestCase {
    func testEveryTemplatePassesValidationInEveryMode() {
        let moneyModes = [MoneySettings(enabled: false, maxSpendGBP: 5), MoneySettings(enabled: true, maxSpendGBP: 5),
                          MoneySettings(enabled: true, maxSpendGBP: 50), MoneySettings(enabled: true, maxSpendGBP: 0)]
        for template in MockQuestCatalog.templates {
            let difficulty = DifficultyPreference.allCases.first { $0 != .any && $0.range.contains(template.difficulty) } ?? .any
            // People templates only run with people quests on; solo ones must pass either way.
            let peopleModes = template.involvesPeople ? [true] : [false, true]
            for scope in template.scopes {
                for money in moneyModes {
                    for allowPeople in peopleModes {
                        var context = makeContext(scope: scope, money: money, venue: scope == .venue ? sampleVenue : nil,
                                                  difficulty: difficulty, allowPeople: allowPeople)
                        context.mode = template.mode
                        for _ in 0..<3 {  // places are picked at random
                            let quest = template.makeQuest(context: context)
                            let violations = QuestRulesValidator.validate(quest, context: context)
                            XCTAssertEqual(violations, [], "\(template.title) [\(scope), money \(money.enabled) £\(money.maxSpendGBP), people \(allowPeople)]")
                        }
                    }
                }
            }
        }
    }

    func testDemoHardQuestsAreHardInEveryScope() async throws {
        let mock = MockAIProvider(latencySeconds: 0)
        for scope in QuestScope.allCases {
            for _ in 0..<8 {
                let context = makeContext(scope: scope, venue: scope == .venue ? sampleVenue : nil, difficulty: .hard)
                let quest = try await mock.generateQuest(context: context)
                XCTAssertGreaterThanOrEqual(quest.difficulty, 4, "\(scope): \(quest.title)")
                XCTAssertEqual(QuestRulesValidator.validate(quest, context: context), [], "\(scope): \(quest.title)")
            }
        }
    }

    func testDemoPeopleQuestsOnlyWhenAllowed() async throws {
        let mock = MockAIProvider(latencySeconds: 0)
        var sawPeople = false
        for _ in 0..<30 {
            let solo = try await mock.generateQuest(context: makeContext(scope: .venue, venue: sampleVenue, difficulty: .hard))
            XCTAssertFalse(solo.involvesPeople)
            let social = try await mock.generateQuest(context: makeContext(scope: .venue, venue: sampleVenue, difficulty: .hard, allowPeople: true))
            sawPeople = sawPeople || social.involvesPeople
        }
        XCTAssertTrue(sawPeople, "People mode should sometimes offer a social quest")
    }

    func testMockVerdictModes() async throws {
        for outcome in Verdict.Outcome.allCases {
            let mock = MockAIProvider(verdictMode: .auto, testPhotoOutcome: { outcome }, latencySeconds: 0)
            let verdict = try await mock.verify(photos: [Data()], criteria: ["a", "b"], quest: makeQuest(), useStrongerModel: false)
            XCTAssertEqual(verdict.verdict, outcome)
            XCTAssertEqual(verdict.criteria.map(\.criterion), ["a", "b"])
        }
    }

    func testMockQuestUsesRealPlaces() async throws {
        let mock = MockAIProvider(latencySeconds: 0)
        for _ in 0..<10 {
            let quest = try await mock.generateQuest(context: makeContext())
            XCTAssertTrue(quest.targetsAnyPlace || samplePlaces.map(\.name).contains(quest.targetPlace))
        }
    }
}

final class VerdictPolicyTests: XCTestCase {
    func verdict(_ outcome: Verdict.Outcome, confidence: Double, met: [Bool]) -> Verdict {
        Verdict(verdict: outcome, criteria: met.enumerated().map { .init(criterion: "c\($0.offset)", met: $0.element, reason: "") },
                confidence: confidence, feedback: "x")
    }

    func testConfidentClearFailStaysFail() {
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.fail, confidence: 0.9, met: [false, false])).verdict, .fail)
    }

    func testLowConfidenceFailBecomesUnsure() {
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.fail, confidence: 0.4, met: [false, false])).verdict, .unsure)
    }

    func testFailWithMostCriteriaMetBecomesUnsure() {
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.fail, confidence: 0.9, met: [true, false])).verdict, .unsure)
    }

    func testUnsureWithEverythingMetPasses() {
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.unsure, confidence: 0.5, met: [true, true])).verdict, .pass)
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.unsure, confidence: 0.5, met: [true, false])).verdict, .unsure)
    }

    func testPassIsUntouched() {
        XCTAssertEqual(VerdictPolicy.applyLeniency(verdict(.pass, confidence: 0.2, met: [false])).verdict, .pass)
    }
}
