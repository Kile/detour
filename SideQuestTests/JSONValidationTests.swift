import XCTest
@testable import SideQuest

final class JSONValidationTests: XCTestCase {
    func testValidQuestDecodes() throws {
        let quest = try QuestJSON.decode(questJSON())
        XCTAssertEqual(quest.title, "Door Collector")
        XCTAssertEqual(quest.targetPlace, "any")
        XCTAssertEqual(quest.successCriteria.count, 2)
        XCTAssertFalse(quest.requiresPurchase)
    }

    func testMissingFieldIsRejected() {
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(removing: ["free_path"]))) { error in
            XCTAssertEqual(error as? AIJSONError, .invalid("missing field \"free_path\""))
        }
    }

    func testWrongTypeIsRejected() {
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["difficulty": "hard"])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["success_criteria": "a door"])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["requires_purchase": "no"])))
    }

    func testOutOfRangeValuesAreRejected() {
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["difficulty": 9])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["points": 0])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["optional_cost_estimate": -1])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["success_criteria": [String]()])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["title": "   "])))
        XCTAssertThrowsError(try QuestJSON.decode(questJSON(["free_path": ""])))
    }

    func testNotJSON() {
        XCTAssertThrowsError(try QuestJSON.decode(text: "Sorry, I can't do that.")) { error in
            XCTAssertEqual(error as? AIJSONError, .notJSON)
        }
        XCTAssertThrowsError(try QuestJSON.decode(Data("{not json".utf8)))
    }

    func testExtractsJSONFromFencesAndChatter() throws {
        let text = "Here you go!\n```json\n" + String(data: questJSON(), encoding: .utf8)! + "\n```\nHave fun."
        let quest = try QuestJSON.decode(text: text)
        XCTAssertEqual(quest.title, "Door Collector")
    }

    func testVerdictDecodesAndNormalises() throws {
        let json = """
        {"verdict":"pass","criteria":[{"criterion":"A vase","met":true,"reason":"Visible"},{"criterion":"  ","met":false,"reason":""}],
         "confidence":87,"feedback":""}
        """
        let verdict = try VerdictJSON.decode(Data(json.utf8))
        XCTAssertEqual(verdict.verdict, .pass)
        XCTAssertEqual(verdict.confidence, 0.87, accuracy: 0.0001)  // percent → 0...1
        XCTAssertEqual(verdict.criteria.count, 1)                   // blank criterion dropped
        XCTAssertFalse(verdict.feedback.isEmpty)                    // default feedback filled in
    }

    func testVerdictRejectsBadValues() {
        XCTAssertThrowsError(try VerdictJSON.decode(Data(#"{"verdict":"maybe","criteria":[{"criterion":"x","met":true,"reason":"y"}],"confidence":0.5,"feedback":"hi"}"#.utf8)))
        XCTAssertThrowsError(try VerdictJSON.decode(Data(#"{"verdict":"pass","criteria":[],"confidence":0.5,"feedback":"hi"}"#.utf8)))
        XCTAssertThrowsError(try VerdictJSON.decode(Data(#"{"verdict":"pass","confidence":0.5,"feedback":"hi"}"#.utf8)))
    }

    func testVerdictConfidenceIsClamped() throws {
        let verdict = try VerdictJSON.decode(Data(#"{"verdict":"fail","criteria":[{"criterion":"x","met":false,"reason":"y"}],"confidence":-3,"feedback":"no"}"#.utf8))
        XCTAssertEqual(verdict.confidence, 0)
    }

    func testVenueDecodes() throws {
        let json = """
        {"venue_name":"Test Hall","summary":"A hall.","areas":[{"name":"Main room","description":"Big."},{"name":"","description":"x"}],
         "typical_things":[],"events_and_highlights":[],"sponsors":[],"rules_and_etiquette":["No backstage"]}
        """
        let venue = try VenueJSON.decode(Data(json.utf8))
        XCTAssertEqual(venue.venueName, "Test Hall")
        XCTAssertEqual(venue.areas.map(\.name), ["Main room"])
        XCTAssertEqual(venue.allowedTargets, ["Test Hall", "Main room"])
    }

    func testQuestRoundTripsThroughSnakeCase() throws {
        let quest = makeQuest()
        let data = try JSONEncoder().encode(quest)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(object["target_place"])
        XCTAssertNotNil(object["optional_cost_estimate"])
        XCTAssertEqual(try QuestJSON.decode(data), quest)
    }
}
