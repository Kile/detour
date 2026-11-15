import XCTest
import CoreLocation

/// Clicks through the whole app in demo mode (no API key, no cost) and saves screenshots to
/// $SCREENSHOT_DIR (default /tmp/sidequest-shots) and to the test results.
final class DemoFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: Helpers

    func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? "/tmp/sidequest-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    func finishOnboardingInDemoMode() {
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        shot("01-onboarding")
        app.buttons["Next"].tap()
        shot("02-how-it-works")
        app.buttons["Next"].tap()
        shot("03-api-key")
        waitAndTap(app.buttons["Try demo mode"])
        XCTAssertTrue(element("questButton").waitForExistence(timeout: 5))
    }

    func setVenue(_ text: String) {
        waitAndTap(element("scopeChip"))
        let field = element("venueField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        sleep(1)  // let the sheet finish presenting before focusing the field
        field.tap()
        field.typeText(text)
        shot("05-scope-sheet")
        waitAndTap(app.navigationBars.buttons["Done"])
    }

    /// Takes as many test photos as the quest asks for (1-4), then lets checking start.
    func pickTestPhoto(_ outcome: String) {
        let done = [app.buttons["Collect & continue"], app.buttons["Count it!"], app.buttons["Try another photo"],
                    element("buyAnotherTry"), element("sendReviewedPhoto")]
        for _ in 0..<4 {
            waitAndTap(element("takePhoto"))
            waitAndTap(element("testPhoto-\(outcome)"))
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if done.contains(where: \.exists) { return }
                usleep(250_000)
            }
        }
    }

    // MARK: Tests

    func testVenueQuestHappyPath() {
        finishOnboardingInDemoMode()
        shot("04-home-empty")
        setVenue("HackLondon 2026 at Imperial College, South Kensington")

        waitAndTap(element("questButton"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
        shot("06-quest-offered")

        // Reroll once (costs points, never below zero), then accept.
        waitAndTap(element("rerollQuest"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
        waitAndTap(element("acceptQuest"))
        XCTAssertTrue(element("takePhoto").waitForExistence(timeout: 5))
        shot("07-quest-accepted")

        waitAndTap(element("takePhoto"))
        XCTAssertTrue(element("testPhoto-pass").waitForExistence(timeout: 5))
        shot("08-test-photo-picker")
        element("testPhoto-pass").tap()
        // Multi-photo quests need more than one shot.
        if !app.buttons["Collect & continue"].waitForExistence(timeout: 4) && !element("sendReviewedPhoto").exists {
            pickTestPhoto("pass")
        }
        if element("sendReviewedPhoto").exists { element("sendReviewedPhoto").tap() }

        let collect = app.buttons["Collect & continue"]
        XCTAssertTrue(collect.waitForExistence(timeout: 20))
        sleep(2)  // let the points count up
        shot("09-result-pass")
        collect.tap()

        XCTAssertTrue(element("questButton").waitForExistence(timeout: 5))
        shot("10-home-after-quest")

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["Completed quests"].waitForExistence(timeout: 5) || app.staticTexts["COMPLETED QUESTS"].exists)
        shot("11-journal")

        app.tabBars.buttons["Settings"].tap()
        let moneyToggle = app.switches["Quests may include optional spending"]
        // The list only builds rows on screen, so scroll down to the money section.
        var swipes = 0
        while !moneyToggle.waitForExistence(timeout: 2) && swipes < 4 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(moneyToggle.exists)
        shot("12-settings")
        moneyToggle.switches.firstMatch.tap()
        if !app.sliders.firstMatch.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        shot("13-settings-money-on")
    }

    func testOpenInMapsOffersAppleAndGoogleMaps() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-settings.onboardingComplete", "YES", "-settings.provider", "demo",
                               "-settings.scope", "nearby", "-mockForcedQuest", "Plaque Hunter"]
        app.launch()
        // Relaunching drops the scheme's simulated location, so set one (Covent Garden).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 51.5117, longitude: -0.1240))
        waitAndTap(element("questButton"))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once"] {
            let allow = springboard.buttons[label]
            if allow.waitForExistence(timeout: 4) { allow.tap(); break }
        }
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 30))
        sleep(2)  // let map tiles load
        shot("18-quest-with-open-in-maps")
        waitAndTap(element("openInMaps"))
        XCTAssertTrue(app.buttons["Apple Maps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Google Maps"].exists)
        shot("19-open-in-maps-menu")
    }

    func testUnsureAndFailPaths() {
        finishOnboardingInDemoMode()
        setVenue("Science Museum, London")

        // Unsure → optional retake, or count it.
        waitAndTap(element("questButton"))
        waitAndTap(element("acceptQuest"), timeout: 20)
        pickTestPhoto("unsure")
        let countIt = app.buttons["Count it!"]
        XCTAssertTrue(countIt.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Retake"].exists)
        XCTAssertTrue(app.buttons["Re-check"].exists)
        shot("14-result-unsure")
        countIt.tap()
        waitAndTap(app.buttons["Collect & continue"], timeout: 10)

        // Fail → try another photo (the last free try) → fail → buy another try → pass.
        waitAndTap(element("questButton"))
        waitAndTap(element("acceptQuest"), timeout: 20)
        pickTestPhoto("fail")
        let tryAgain = app.buttons["Try another photo"]
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["1 try left"].exists)
        shot("15-result-fail")
        tryAgain.tap()
        XCTAssertTrue(element("triesLeft").waitForExistence(timeout: 5))
        pickTestPhoto("fail")
        let buy = element("buyAnotherTry")
        XCTAssertTrue(buy.waitForExistence(timeout: 20))
        XCTAssertFalse(tryAgain.exists)
        shot("16-result-buy-another-try")
        if buy.isEnabled {
            buy.tap()
            pickTestPhoto("pass")
            waitAndTap(app.buttons["Collect & continue"], timeout: 20)
        } else {
            // The first quest's points may not cover this quest's price.
            waitAndTap(app.buttons["Give up this quest"])
        }
        XCTAssertTrue(element("questButton").waitForExistence(timeout: 5))
    }

    func testNearbyQuestUsesLocationAndMap() {
        finishOnboardingInDemoMode()
        waitAndTap(element("scopeChip"))
        waitAndTap(app.buttons["Nearby"])
        waitAndTap(app.navigationBars.buttons["Done"])

        waitAndTap(element("questButton"))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once"] {
            let allow = springboard.buttons[label]
            if allow.waitForExistence(timeout: 4) { allow.tap(); break }
        }
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 30))
        sleep(2)  // let map tiles load
        shot("16-nearby-quest")
        element("acceptQuest").tap()
        pickTestPhoto("pass")

        // Either we're inside the quest radius (result) or the geofence asks us to get closer.
        let collect = app.buttons["Collect & continue"]
        let tooFar = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Get a bit closer'")).firstMatch
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline && !collect.exists && !tooFar.exists { usleep(300_000) }
        XCTAssertTrue(collect.exists || tooFar.exists)
        shot("17-nearby-after-photo")
    }

    func testDiscardNewSettingsAndPeopleQuest() {
        finishOnboardingInDemoMode()
        setVenue("HackLondon 2026 at Imperial College")
        waitAndTap(element("questButton"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))

        // Change settings from the quest card: Hard + people quests.
        waitAndTap(element("nextQuestSettings"))
        waitAndTap(app.segmentedControls.buttons["Hard"])
        let people = app.switches["peopleToggle"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.switches.firstMatch.tap()
        waitAndTap(app.navigationBars.buttons["Done"])
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'new settings'")).firstMatch.waitForExistence(timeout: 5))
        shot("18-reroll-new-settings")

        // Discard, then get a fresh quest with the new settings.
        waitAndTap(element("discardQuest"))
        XCTAssertTrue(element("questButton").waitForExistence(timeout: 5))
        shot("19-home-after-discard")
        waitAndTap(element("questButton"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))

        // Reroll until a people quest turns up (demo picks them about half the time).
        for _ in 0..<8 where !app.staticTexts["People"].exists {
            waitAndTap(element("rerollQuest"))
            XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
        }
        shot("20-hard-people-quest")
        waitAndTap(element("acceptQuest"))
        pickTestPhoto("pass")
        if element("sendReviewedPhoto").waitForExistence(timeout: 15) {
            shot("21-photo-review")
            element("sendReviewedPhoto").tap()
        }
        XCTAssertTrue(app.buttons["Collect & continue"].waitForExistence(timeout: 20))
    }

    func testMultiPhotoQuestUsesATray() {
        finishOnboardingInDemoMode()
        setVenue("HackLondon 2026 at Imperial College")
        waitAndTap(element("scopeChip"))
        waitAndTap(app.segmentedControls.buttons["Hard"])
        waitAndTap(app.navigationBars.buttons["Done"])
        waitAndTap(element("questButton"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
        let multi = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'one per find'")).firstMatch
        for _ in 0..<12 where !multi.exists {
            waitAndTap(element("rerollQuest"))
            XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
            sleep(1)
        }
        XCTAssertTrue(multi.exists, "Expected a multi-photo quest")
        shot("22-multi-photo-quest")
        waitAndTap(element("acceptQuest"))
        waitAndTap(element("takePhoto"))
        waitAndTap(element("testPhoto-pass"))
        XCTAssertTrue(element("checkNow").waitForExistence(timeout: 5), "Partial set offers Check now")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Take photo 2 of'")).firstMatch.exists)
        shot("23-photo-tray")
        pickTestPhoto("pass")
        if element("sendReviewedPhoto").exists { element("sendReviewedPhoto").tap() }
        XCTAssertTrue(app.buttons["Collect & continue"].waitForExistence(timeout: 20))
        sleep(2)
        shot("24-multi-photo-result")
    }

    func testPhotoChallengeWithTimeTrial() {
        finishOnboardingInDemoMode()
        app.tabBars.buttons["Settings"].tap()
        let timeTrial = app.switches["timeTrialToggle"]
        for _ in 0..<6 where !timeTrial.exists { app.swipeUp() }
        XCTAssertTrue(timeTrial.waitForExistence(timeout: 5))
        timeTrial.switches.firstMatch.tap()
        shot("25-settings-time-trial")
        app.tabBars.buttons["Quest"].tap()

        waitAndTap(element("mode-photo"))
        setVenue("HackLondon 2026 at Imperial College")
        shot("26-home-photo-mode")
        waitAndTap(element("questButton"))
        XCTAssertTrue(element("acceptQuest").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Photo challenge"].exists)
        shot("27-photo-challenge-offered")
        waitAndTap(element("acceptQuest"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'left'")).firstMatch.waitForExistence(timeout: 5),
                      "Countdown is running")
        sleep(2)
        shot("28-time-trial-countdown")
        pickTestPhoto("pass")
        if element("sendReviewedPhoto").exists { element("sendReviewedPhoto").tap() }
        XCTAssertTrue(app.buttons["Collect & continue"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Beat the clock'")).firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        shot("29-time-trial-result")
    }
}
