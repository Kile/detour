import XCTest
@testable import SideQuest

final class SafetyValidatorTests: XCTestCase {
    let day = SafetyValidator.Context(scope: .nearby, isNightTime: false)
    let night = SafetyValidator.Context(scope: .nearby, isNightTime: true)
    let venue = SafetyValidator.Context(scope: .venue, isNightTime: false)

    func violations(_ description: String, context: SafetyValidator.Context? = nil) -> [QuestViolation] {
        SafetyValidator.validate(makeQuest(description: description), context: context ?? day)
    }

    func testCleanQuestPasses() {
        XCTAssertEqual(SafetyValidator.validate(makeQuest(), context: day), [])
    }

    func testPhotographingPeopleIsRejected() {
        for text in ["Photograph a stranger wearing a hat.", "Take a photo of the barista making coffee.",
                     "Snap a picture of people dancing.", "Take a selfie with a stranger."] {
            XCTAssertFalse(violations(text).isEmpty, "Should reject: \(text)")
        }
    }

    func testTalkingAndPeopleFreePhotosAreFine() {
        for text in ["Photograph the mural without any people in it.",
                     "Snap the barista's latte art.",
                     "Photograph the staff picks shelf in the bookshop.",
                     "Find a statue with a funny face and photograph it."] {
            XCTAssertEqual(violations(text), [], "Should allow: \(text)")
        }
    }

    func testCriteriaMustNotNeedAPerson() {
        let quest = makeQuest(successCriteria: ["A person is holding the sign", "The sign is red"])
        XCTAssertFalse(SafetyValidator.validate(quest, context: day).isEmpty)
        let ok = makeQuest(successCriteria: ["No people are visible", "The sign is red"])
        XCTAssertEqual(SafetyValidator.validate(ok, context: day), [])
    }

    func testRestrictedAndDangerousActivitiesAreRejected() {
        for text in ["Sneak into the staff-only area.", "Climb over the fence to see the garden.",
                     "Get onto the roof for the view.", "Walk along the railway tracks.",
                     "Explore the abandoned warehouse.", "Stand in the road for the best angle.",
                     "Find a secluded spot by the river."] {
            XCTAssertFalse(violations(text).isEmpty, "Should reject: \(text)")
        }
    }

    func testNegatedWarningsAreFine() {
        for text in ["Find the gallery's best painting. Don't go into staff-only areas.",
                     "Photograph the view from the bridge — no need to climb on anything.",
                     "Climb the stairs to the first floor and find a clock."] {
            XCTAssertEqual(violations(text), [], "Should allow: \(text)")
        }
    }

    func testAlcoholGamblingAndAgeRestrictedAreRejected() {
        for text in ["Find the oldest pub in town.", "Photograph a pint glass.", "Visit the casino.",
                     "Find a vape shop sign.", "Head to the cocktail bar.", "Find a bar with a red door."] {
            XCTAssertFalse(violations(text).isEmpty, "Should reject: \(text)")
        }
    }

    func testHarmlessBarsAreFine() {
        for text in ["Find a chocolate bar with a funny wrapper.", "Photograph the salad bar display.",
                     "Find a snack bar sign."] {
            XCTAssertEqual(violations(text), [], "Should allow: \(text)")
        }
    }

    func testDisruptionIsRejected() {
        for text in ["Rearrange the books into a rainbow.", "Block the doorway for a dramatic shot.",
                     "Stand on a table for a better angle.", "Play a prank on the shop."] {
            XCTAssertFalse(violations(text).isEmpty, "Should reject: \(text)")
        }
    }

    func testIsolatedPlacesOnlyRejectedAtNight() {
        let text = "Find the oldest tree in Russell Square park and photograph its bark."
        XCTAssertEqual(violations(text, context: day), [])
        XCTAssertFalse(violations(text, context: night).isEmpty)
    }

    func testVenueEtiquette() {
        for text in ["Walk onto the stage and wave.", "Grab the mic during a break.", "Count the slides during the keynote."] {
            XCTAssertFalse(violations(text, context: venue).isEmpty, "Should reject: \(text)")
        }
        XCTAssertEqual(violations("Find the stage area and photograph the event banner.", context: venue), [])
        XCTAssertFalse(violations("Interrupt a talk to ask a question.", context: venue).isEmpty)
    }

    func testSafetyNotesAreNotScanned() {
        let quest = makeQuest(safetyNotes: "Parks can be dark at night, and never go into staff-only areas or pubs.")
        XCTAssertEqual(SafetyValidator.validate(quest, context: night), [])
    }
}

final class PlaceValidatorTests: XCTestCase {
    func testAnyIsAllowed() {
        XCTAssertNil(PlaceValidator.violation(targetPlace: "any", allowed: []))
        XCTAssertNil(PlaceValidator.violation(targetPlace: "Any", allowed: ["Somewhere"]))
    }

    func testProvidedPlaceIsAllowedLeniently() {
        let allowed = samplePlaces.map(\.name)
        XCTAssertNil(PlaceValidator.violation(targetPlace: "The British Museum", allowed: allowed))
        XCTAssertNil(PlaceValidator.violation(targetPlace: "british museum", allowed: allowed))
        XCTAssertNil(PlaceValidator.violation(targetPlace: "Gail’s Bakery", allowed: allowed))
        XCTAssertEqual(PlaceValidator.matches("Russell Square, Bloomsbury", allowed: allowed), "Russell Square")
    }

    func testInventedPlaceIsRejected() {
        let violation = PlaceValidator.violation(targetPlace: "Ye Olde Curiosity Shoppe", allowed: samplePlaces.map(\.name))
        XCTAssertEqual(violation?.rule, .place)
        XCTAssertNotNil(PlaceValidator.violation(targetPlace: "Tate Modern", allowed: samplePlaces.map(\.name)))
        XCTAssertNotNil(PlaceValidator.violation(targetPlace: "Somewhere", allowed: []))
    }

    func testShortNamesDoNotMatchBySubstring() {
        XCTAssertNil(PlaceValidator.matches("Bar", allowed: ["Barbican Centre"]))
    }

    func testVenueAreasAreTheAllowedTargets() {
        let context = makeContext(scope: .venue, venue: sampleVenue)
        XCTAssertEqual(QuestRulesValidator.validate(makeQuest(description: "Find the Great Hall's biggest banner and photograph it.",
                                                              targetPlace: "Great Hall"), context: context), [])
        let invented = QuestRulesValidator.validate(makeQuest(targetPlace: "Rooftop Bar"), context: context)
        XCTAssertTrue(invented.contains { $0.rule == .place })
    }

    func testCompositeValidatorCatchesEveryRule() {
        let quest = makeQuest(description: "Buy a pint at the pub.", targetPlace: "Made Up Place", requiresPurchase: true)
        let rules = Set(QuestRulesValidator.validate(quest, context: makeContext()).map(\.rule))
        XCTAssertEqual(rules, [.place, .money, .safety])
    }
}

final class PlaceFilterTests: XCTestCase {
    func testExcludesUnsuitablePlaces() {
        XCTAssertFalse(PlaceFilter.isAllowed(name: "The Lamb and Flag Pub", categoryRawValue: "MKPOICategoryRestaurant"))
        XCTAssertFalse(PlaceFilter.isAllowed(name: "Corner Bar", categoryRawValue: nil))
        XCTAssertFalse(PlaceFilter.isAllowed(name: "Grosvenor Casino", categoryRawValue: nil))
        XCTAssertFalse(PlaceFilter.isAllowed(name: "Fabric", categoryRawValue: "MKPOICategoryNightlife"))
        XCTAssertFalse(PlaceFilter.isAllowed(name: "Vape Lab", categoryRawValue: "MKPOICategoryStore"))
    }

    func testKeepsNormalPlaces() {
        XCTAssertTrue(PlaceFilter.isAllowed(name: "The British Museum", categoryRawValue: "MKPOICategoryMuseum"))
        XCTAssertTrue(PlaceFilter.isAllowed(name: "Barbican Centre", categoryRawValue: nil))
        XCTAssertTrue(PlaceFilter.isAllowed(name: "Gail's Bakery", categoryRawValue: "MKPOICategoryBakery"))
    }

    func testReadableCategory() {
        XCTAssertEqual(PlaceFilter.readableCategory("MKPOICategoryNationalPark"), "national park")
        XCTAssertEqual(PlaceFilter.readableCategory(nil), "place")
    }
}
