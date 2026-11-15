import XCTest
@testable import SideQuest

final class MoneyRulesValidatorTests: XCTestCase {
    let off = MoneySettings(enabled: false, maxSpendGBP: 5)
    let on5 = MoneySettings(enabled: true, maxSpendGBP: 5)

    func testCleanFreeQuestPassesWithMoneyOff() {
        XCTAssertEqual(MoneyRulesValidator.validate(makeQuest(), settings: off), [])
    }

    func testCanonicalAntiqueExamplePassesWithMoneyOff() {
        // "Photograph it together with its label or price tag" is about looking, not paying.
        let quest = makeQuest(
            title: "Antique Hunter",
            description: "Find an antique shop nearby and find a vase that looks at least 50 years old.",
            successCriteria: ["A vase is the main subject", "The vase looks old", "A label or price tag is visible"],
            photoInstructions: "Photograph it together with its label or price tag.",
            freePath: "Look in the shop window or on the shop floor.")
        XCTAssertEqual(MoneyRulesValidator.validate(quest, settings: off), [])
    }

    // MARK: Toggle off

    func testMoneyOffRejectsAnyMentionOfBuying() {
        let quest = makeQuest(description: "Find a bakery and buy the strangest pastry.")
        let violations = MoneyRulesValidator.validate(quest, settings: off)
        XCTAssertTrue(violations.contains { $0.message.contains("mentions buying") }, "\(violations)")
    }

    func testMoneyOffRejectsEvenReassuringMentions() {
        let quest = makeQuest(description: "No need to buy anything — just admire the cakes.")
        XCTAssertFalse(MoneyRulesValidator.validate(quest, settings: off).isEmpty)
    }

    func testMoneyOffRejectsTicketsFeesAndAmounts() {
        for text in ["Grab a ticket to the gallery.", "There's a small entry fee.", "It costs £3 to go in.",
                     "Pay at the till.", "Order a hot chocolate.", "Bring 5 pounds.", "Rent a bike nearby.",
                     "Make a donation to the museum.", "Grab a coffee on the way."] {
            let quest = makeQuest(description: "Find a gallery. \(text)")
            XCTAssertFalse(MoneyRulesValidator.validate(quest, settings: off).isEmpty, "Should reject: \(text)")
        }
    }

    func testMoneyOffRequiresZeroCost() {
        let quest = makeQuest(optionalCostEstimate: 2)
        let violations = MoneyRulesValidator.validate(quest, settings: off)
        XCTAssertTrue(violations.contains { $0.message.contains("must be 0") })
    }

    func testMoneyOffAllowsPhrasesThatAreNotAboutMoney() {
        for text in ["Pay attention to the carvings above the door.", "Pay a visit to the square.",
                     "Spend five minutes looking around.", "Find the most expensive-looking shop window."] {
            let quest = makeQuest(description: "Find a building with a carved door. \(text)")
            XCTAssertEqual(MoneyRulesValidator.validate(quest, settings: off), [], "Should allow: \(text)")
        }
    }

    // MARK: requires_purchase and free path

    func testRequiresPurchaseTrueIsAlwaysRejected() {
        for settings in [off, on5] {
            let violations = MoneyRulesValidator.validate(makeQuest(requiresPurchase: true), settings: settings)
            XCTAssertTrue(violations.contains { $0.message.contains("requires_purchase") })
        }
    }

    func testMissingFreePathIsRejected() {
        for settings in [off, on5] {
            for freePath in ["", "   ", "Free."] {
                let violations = MoneyRulesValidator.validate(makeQuest(freePath: freePath), settings: settings)
                XCTAssertTrue(violations.contains { $0.message.contains("free_path is missing") }, "\(freePath)")
            }
        }
    }

    // MARK: Toggle on

    func testOptionalPurchaseWithinCapPasses() {
        let quest = makeQuest(
            description: "Find a postcard rack and pick your favourite design. You could buy it (about £1) — or just photograph it.",
            optionalCostEstimate: 1,
            freePath: "Photograph your favourite postcard on the rack.")
        XCTAssertEqual(MoneyRulesValidator.validate(quest, settings: on5), [])
    }

    func testCostOverCapIsRejected() {
        let quest = makeQuest(description: "You could buy a print.", optionalCostEstimate: 12,
                              freePath: "Photograph the print in the window.")
        let violations = MoneyRulesValidator.validate(quest, settings: on5)
        XCTAssertTrue(violations.contains { $0.message.contains("above the £5 limit") }, "\(violations)")
    }

    func testAmountInTextOverCapIsRejected() {
        let quest = makeQuest(description: "You could buy a vintage map for £18.", optionalCostEstimate: 4,
                              freePath: "Photograph the maps in the window.")
        XCTAssertTrue(MoneyRulesValidator.validate(quest, settings: on5).contains { $0.message.contains("£18.00") })
    }

    func testZeroCapBehavesLikeNoSpending() {
        let quest = makeQuest(description: "You could buy a sticker.", optionalCostEstimate: 1,
                              freePath: "Photograph the stickers on display.")
        let violations = MoneyRulesValidator.validate(quest, settings: MoneySettings(enabled: true, maxSpendGBP: 0))
        XCTAssertFalse(violations.isEmpty)
    }

    func testPurchaseMentionWithoutEstimateIsRejected() {
        let quest = makeQuest(description: "You could buy a croissant.", optionalCostEstimate: 0,
                              freePath: "Photograph the croissants in the window.")
        XCTAssertTrue(MoneyRulesValidator.validate(quest, settings: on5).contains { $0.message.contains("give an estimate") })
    }

    func testFreePathMustBeFree() {
        let quest = makeQuest(description: "Find or buy a postcard.", optionalCostEstimate: 1,
                              freePath: "Buy the cheapest postcard you can find.")
        XCTAssertTrue(MoneyRulesValidator.validate(quest, settings: on5).contains { $0.message.contains("free_path") })
    }

    func testCriteriaMustNotRequireBuying() {
        let quest = makeQuest(description: "Find or buy a postcard.", successCriteria: ["A receipt is visible"],
                              optionalCostEstimate: 1, freePath: "Photograph a postcard on the rack.")
        XCTAssertTrue(MoneyRulesValidator.validate(quest, settings: on5).contains { $0.message.contains("success_criteria") })
    }

    // MARK: Pressure and pay-to-win (both modes)

    func testPressureIsRejected() {
        for text in ["You should buy one.", "Treat yourself to a cake!", "Don't miss out on the special.",
                     "It's only £2!", "Support the shop by buying something."] {
            let quest = makeQuest(description: "Find a bakery. \(text)", optionalCostEstimate: 2,
                                  freePath: "Photograph the window display.")
            XCTAssertFalse(MoneyRulesValidator.validate(quest, settings: on5).isEmpty, "Should reject: \(text)")
        }
    }

    func testPayToWinIsRejected() {
        let quest = makeQuest(description: "Find a cake. Bonus points if you buy it!", optionalCostEstimate: 3,
                              freePath: "Photograph a cake in the window.")
        XCTAssertTrue(MoneyRulesValidator.validate(quest, settings: on5).contains { $0.message.contains("pay-to-win") })
    }

    func testStatedAmountsParsing() {
        XCTAssertEqual(MoneyRulesValidator.statedAmounts(in: "about £3.50 or 4 quid, maybe £10"), [3.5, 4, 10])
    }
}
