import XCTest
@testable import SideQuest

final class ScoringTests: XCTestCase {
    func testAwardIsPointsTimesDifficulty() {
        XCTAssertEqual(Scoring.award(points: 20, difficulty: 3), 60)
        XCTAssertEqual(Scoring.award(points: 10, difficulty: 1), 10)
    }

    func testAwardClampsInflatedValues() {
        XCTAssertEqual(Scoring.award(points: 500, difficulty: 9), 50 * 5)
        XCTAssertEqual(Scoring.award(points: 0, difficulty: 0), 5 * 1)
    }

    func testFreeAndPaidPathsEarnTheSame() {
        // Points depend only on the quest, never on whether the player spent money.
        let free = makeQuest(points: 30, optionalCostEstimate: 0)
        let paid = makeQuest(points: 30, optionalCostEstimate: 4)
        XCTAssertEqual(Scoring.award(points: free.points, difficulty: free.difficulty),
                       Scoring.award(points: paid.points, difficulty: paid.difficulty))
    }

    func testRerollCostNeverGoesNegative() {
        XCTAssertEqual(Scoring.pointsAfterReroll(100), 95)
        XCTAssertEqual(Scoring.pointsAfterReroll(3), 0)
        XCTAssertEqual(Scoring.pointsAfterReroll(0), 0)
    }

    func testLevels() {
        XCTAssertEqual(Scoring.level(forXP: 0), 1)
        XCTAssertEqual(Scoring.level(forXP: 99), 1)
        XCTAssertEqual(Scoring.level(forXP: 100), 2)
        XCTAssertEqual(Scoring.level(forXP: 299), 2)
        XCTAssertEqual(Scoring.level(forXP: 300), 3)
        XCTAssertEqual(Scoring.level(forXP: 1_000), 5)
        let progress = Scoring.levelProgress(xp: 150)
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.intoLevel, 50)
        XCTAssertEqual(progress.levelSize, 200)
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }
}

final class StreakTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func testFirstCompletionStartsStreak() {
        XCTAssertEqual(Streak.updated(current: 0, lastCompletionDay: nil, completionDate: day(10), calendar: calendar), 1)
    }

    func testSameDayKeepsStreak() {
        XCTAssertEqual(Streak.updated(current: 3, lastCompletionDay: day(10, hour: 9), completionDate: day(10, hour: 21), calendar: calendar), 3)
    }

    func testNextDayExtendsStreak() {
        XCTAssertEqual(Streak.updated(current: 3, lastCompletionDay: day(10, hour: 23), completionDate: day(11, hour: 1), calendar: calendar), 4)
    }

    func testGapResetsStreak() {
        XCTAssertEqual(Streak.updated(current: 5, lastCompletionDay: day(10), completionDate: day(12), calendar: calendar), 1)
    }

    func testDisplayedStreakLapses() {
        XCTAssertEqual(Streak.displayed(current: 4, lastCompletionDay: day(10), now: day(11), calendar: calendar), 4)
        XCTAssertEqual(Streak.displayed(current: 4, lastCompletionDay: day(10), now: day(12), calendar: calendar), 0)
        XCTAssertEqual(Streak.displayed(current: 0, lastCompletionDay: nil, now: day(12), calendar: calendar), 0)
    }
}

final class BadgeTests: XCTestCase {
    func testBadges() {
        XCTAssertEqual(BadgeEngine.earned(PlayerStats()), [])
        XCTAssertEqual(BadgeEngine.earned(PlayerStats(completedCount: 1, scopes: [.venue], maxDifficulty: 2, streak: 1)), [.firstQuest])
        let veteran = PlayerStats(completedCount: 12, scopes: Set(QuestScope.allCases), themes: Set(QuestTheme.allCases),
                                  maxDifficulty: 5, streak: 3, level: 5, photoChallenges: 3, clockBeats: 3)
        XCTAssertEqual(BadgeEngine.earned(veteran), Set(Badge.allCases))
    }
}

final class GeofenceTests: XCTestCase {
    let museum = GeoPoint(latitude: 51.519413, longitude: -0.126957)

    func testDistanceIsSensible() {
        let paris = GeoPoint(latitude: 48.8566, longitude: 2.3522)
        XCTAssertEqual(Geofence.distance(museum, paris), 343_000, accuracy: 5_000)
        XCTAssertEqual(Geofence.distance(museum, museum), 0, accuracy: 0.001)
    }

    func testInsideRadius() {
        let nearby = GeoPoint(latitude: 51.5203, longitude: -0.1270)  // ~100 m north
        guard case .inside = Geofence.check(user: nearby, horizontalAccuracy: 10, center: museum, radius: 200) else {
            return XCTFail("Expected inside")
        }
    }

    func testOutsideRadius() {
        let coventGarden = GeoPoint(latitude: 51.51174, longitude: -0.12302)  // ~900 m away
        guard case .outside(let distance, let radius) = Geofence.check(user: coventGarden, horizontalAccuracy: 10, center: museum, radius: 200) else {
            return XCTFail("Expected outside")
        }
        XCTAssertGreaterThan(distance, 800)
        XCTAssertEqual(radius, 200)
    }

    func testAccuracyGivesALittleSlackButNotUnlimited() {
        let edge = GeoPoint(latitude: 51.5214, longitude: -0.1270)   // ~220 m away
        guard case .inside = Geofence.check(user: edge, horizontalAccuracy: 50, center: museum, radius: 200) else {
            return XCTFail("Expected inside thanks to accuracy slack")
        }
        let farther = GeoPoint(latitude: 51.5230, longitude: -0.1270)  // ~400 m away
        guard case .outside = Geofence.check(user: farther, horizontalAccuracy: 900, center: museum, radius: 200) else {
            return XCTFail("Slack is capped at 100 m")
        }
    }

    func testTooInaccurateFix() {
        XCTAssertEqual(Geofence.check(user: museum, horizontalAccuracy: 3_000, center: museum, radius: 200), .tooInaccurate(accuracy: 3_000))
        XCTAssertEqual(Geofence.check(user: museum, horizontalAccuracy: -1, center: museum, radius: 200), .tooInaccurate(accuracy: -1))
    }

    func testRadiusPerScope() {
        XCTAssertEqual(Geofence.radius(scope: .nearby, hasSpecificTarget: true), 200)
        XCTAssertEqual(Geofence.radius(scope: .nearby, hasSpecificTarget: false), 1_500)
        XCTAssertGreaterThan(Geofence.radius(scope: .city, hasSpecificTarget: false), 10_000)
    }
}
