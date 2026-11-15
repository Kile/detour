import XCTest

/// Captures clean screens for the App Store / Devpost mockups (see README → Store screenshots).
/// Uses demo mode, sample history (`-marketing`, debug builds only) and fixed demo quests.
/// Saves to $MARKETING_DIR (default /tmp/detour-marketing/raw).
final class MarketingScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    func launch(_ extra: [String: String]) {
        app = XCUIApplication()
        var args = ["-ui-testing", "-marketing",
                    "-settings.onboardingComplete", "YES",
                    "-settings.provider", "demo",
                    "-settings.venueDescription", "HackLondon 2026 at Imperial College"]
        for (key, value) in extra { args += ["-\(key)", value] }
        app.launchArguments = args
        app.launch()
    }

    func save(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["MARKETING_DIR"] ?? "/tmp/detour-marketing/raw"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func getQuest(allowLocation: Bool = false) {
        XCTAssertTrue(element("questButton").waitForExistence(timeout: 10))
        element("questButton").tap()
        if allowLocation {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow While Using App", "Allow Once"] where springboard.buttons[label].waitForExistence(timeout: 3) {
                springboard.buttons[label].tap()
                break
            }
        }
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 30))
    }

    func test1Home() {
        launch(["settings.scope": "venue"])
        XCTAssertTrue(element("questButton").waitForExistence(timeout: 10))
        sleep(1)
        save("01-home")
    }

    func test2NearbyQuestWithMap() {
        launch(["settings.scope": "nearby", "mockForcedQuest": "Plaque Hunter", "mockPlaceHint": "Seven Dials",
                "mockPlace": "Seven Dials|51.51405|-0.12693|landmark"])
        getQuest(allowLocation: true)
        sleep(4)   // map tiles
        save("02-nearby-quest")
    }

    func test3HardPeopleQuest() {
        launch(["settings.scope": "venue", "settings.difficulty": "hard", "settings.allowPeople": "YES",
                "mockForcedQuest": "Monster Census"])
        getQuest()
        sleep(1)
        save("03-hard-people-quest")
    }

    func test4PhotoChallengeWithWeather() {
        launch(["settings.scope": "nearby", "settings.mode": "photo", "settings.timeTrial": "YES",
                "settings.difficulty": "hard", "mockForcedQuest": "Umbrella Street", "mockWeather": "rain",
                "mockPlaceHint": "Royal Opera House",
                "mockPlace": "Royal Opera House|51.51290|-0.12220|theatre"])
        getQuest(allowLocation: true)
        sleep(2)
        save("04-photo-challenge")
    }

    func test5Result() {
        launch(["settings.scope": "nearby", "settings.timeTrial": "YES", "mockForcedQuest": "Antique Hunter"])
        getQuest(allowLocation: true)
        element("acceptQuest").tap()
        XCTAssertTrue(element("takePhoto").waitForExistence(timeout: 5))
        element("takePhoto").tap()
        XCTAssertTrue(element("testPhoto-pass").waitForExistence(timeout: 5))
        element("testPhoto-pass").tap()
        if element("sendReviewedPhoto").waitForExistence(timeout: 4) { element("sendReviewedPhoto").tap() }
        XCTAssertTrue(app.buttons["Collect & continue"].waitForExistence(timeout: 20))
        sleep(2)   // points count up, confetti mid-air
        save("05-result")
    }

    func test6Journal() {
        launch(["settings.scope": "venue"])
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Journal"].tap()
        sleep(1)
        save("06-journal")
    }
}
