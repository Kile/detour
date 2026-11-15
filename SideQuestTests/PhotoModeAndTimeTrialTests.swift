import XCTest
import SwiftData
@testable import SideQuest

final class TimeTrialTests: XCTestCase {
    func minutes(_ seconds: TimeInterval) -> Int { Int(seconds / 60) }

    func testHarderAndFurtherMeansMoreTime() {
        let easyHere = TimeTrial.limit(difficulty: 1, distanceMeters: nil, scope: .nearby)
        let hardHere = TimeTrial.limit(difficulty: 5, distanceMeters: nil, scope: .nearby)
        let hardFar = TimeTrial.limit(difficulty: 5, distanceMeters: 1_200, scope: .nearby)
        XCTAssertLessThan(easyHere, hardHere)
        XCTAssertLessThan(hardHere, hardFar)
    }

    func testWorkedExamples() {
        // Easy, "anywhere" nearby: 3 min to find + ~2.5 min walking ≈ 6 min.
        XCTAssertEqual(minutes(TimeTrial.limit(difficulty: 1, distanceMeters: nil, scope: .nearby)), 6)
        // Hard quest at a museum 420 m away: 13 min + 7 min walking = 20 min.
        XCTAssertEqual(minutes(TimeTrial.limit(difficulty: 4, distanceMeters: 420, scope: .nearby)), 20)
        // Hard city quest 3 km away: walk 2 km + ride 1 km (≈ 38 min) + 13 min ≈ 52 min.
        XCTAssertEqual(minutes(TimeTrial.limit(difficulty: 4, distanceMeters: 3_000, scope: .city)), 52)
    }

    func testMorePhotosMeansMoreTimeAndLimitsAreClamped() {
        XCTAssertGreaterThan(TimeTrial.limit(difficulty: 3, distanceMeters: 100, scope: .venue, photoCount: 3),
                             TimeTrial.limit(difficulty: 3, distanceMeters: 100, scope: .venue, photoCount: 1))
        XCTAssertEqual(minutes(TimeTrial.limit(difficulty: 5, distanceMeters: 100_000, scope: .city)), 120)
        XCTAssertGreaterThanOrEqual(minutes(TimeTrial.limit(difficulty: 1, distanceMeters: 0, scope: .venue)), 2)
    }

    func testBonusAndFormatting() {
        XCTAssertEqual(TimeTrial.bonus(for: 100), 50)
        XCTAssertEqual(TimeTrial.format(65), "1:05")
        XCTAssertEqual(TimeTrial.format(3_725), "1:02:05")
        XCTAssertEqual(TimeTrial.format(-5), "0:00")
    }

    func testFingerprintMentionsModeAndTimeTrial() {
        var settings = QuestSettingsFingerprint(scope: .nearby, venue: "", theme: nil, difficulty: .any, allowPeople: false, money: .default)
        let before = settings
        settings.mode = .photo
        settings.timeTrial = true
        XCTAssertEqual(settings.changes(since: before), ["Photo challenges", "Time trial on"])
        XCTAssertTrue(settings.labels.contains("⏱ Time trial"))
        XCTAssertTrue(settings.labels.contains("📷 Photo"))
    }
}

final class WeatherTests: XCTestCase {
    /// A real Open-Meteo response for central London (fetched while building this feature).
    let londonOvercast = Data(#"{"latitude":51.51147,"longitude":-0.13078308,"generationtime_ms":0.11,"utc_offset_seconds":0,"timezone":"Europe/London","timezone_abbreviation":"GMT","elevation":31.0,"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","precipitation":"mm","weather_code":"wmo code","cloud_cover":"%","wind_speed_10m":"km/h","is_day":""},"current":{"time":"2026-11-15T10:15","interval":900,"temperature_2m":7.2,"precipitation":0.00,"weather_code":3,"cloud_cover":100,"wind_speed_10m":4.7,"is_day":1},"daily_units":{"time":"iso8601","sunrise":"iso8601","sunset":"iso8601"},"daily":{"time":["2026-11-15"],"sunrise":["2026-11-15T07:18"],"sunset":["2026-11-15T16:11"]}}"#.utf8)

    func testParsesOpenMeteo() throws {
        let weather = try WeatherService.parse(londonOvercast)
        XCTAssertEqual(weather.condition, "overcast")
        XCTAssertEqual(weather.temperatureC, 7.2, accuracy: 0.01)
        XCTAssertTrue(weather.isDay)
        XCTAssertFalse(weather.isWet)
        XCTAssertFalse(weather.isSunny)
        XCTAssertEqual(weather.sunset, "16:11")
        XCTAssertEqual(weather.observedAt, "10:15")
        XCTAssertFalse(weather.goldenHour)
        XCTAssertEqual(weather.label, "☁️ 7° · overcast")
        XCTAssertEqual(weather.promptLines, ["WEATHER: overcast, 7°C, wind 5 km/h", "LIGHT: daylight, sunset at 16:11"])
    }

    func testRainGoldenHourAndStorms() {
        let rain = WeatherSnapshot(temperatureC: 11, weatherCode: 61, precipitationMM: 0.6, cloudCover: 100, windKmh: 14,
                                   isDay: true, sunrise: "07:18", sunset: "16:11", observedAt: "15:30")
        XCTAssertTrue(rain.isWet)
        XCTAssertEqual(rain.condition, "light rain")
        XCTAssertTrue(rain.goldenHour)
        XCTAssertTrue(rain.promptLines[1].contains("golden hour"))
        let storm = WeatherSnapshot(temperatureC: 15, weatherCode: 95, precipitationMM: 4, cloudCover: 100, windKmh: 40,
                                    isDay: true, sunrise: nil, sunset: nil, observedAt: nil)
        XCTAssertTrue(storm.promptLines[0].contains("shelter"))
    }

    func testOnlyRoundedLocationIsSent() {
        let url = WeatherService.url(for: GeoPoint(latitude: 51.519413, longitude: -0.126957)).absoluteString
        XCTAssertTrue(url.contains("latitude=51.52"))
        XCTAssertTrue(url.contains("longitude=-0.13"))
        XCTAssertFalse(url.contains("51.519"))
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/"))
    }
}

final class PhotoModePromptTests: XCTestCase {
    func testPhotoModeUsesPhotographerPromptWithWeather() {
        var context = makeContext()
        context.mode = .photo
        context.weather = WeatherSnapshot(temperatureC: 11, weatherCode: 61, precipitationMM: 0.6, cloudCover: 100,
                                          windKmh: 14, isDay: true, sunrise: "07:18", sunset: "16:11", observedAt: "12:00")
        XCTAssertEqual(QuestPrompts.system(for: context), QuestPrompts.photoChallengeSystem)
        XCTAssertTrue(QuestPrompts.photoChallengeSystem.contains("umbrella"))
        let user = QuestPrompts.generationUser(context)
        XCTAssertTrue(user.contains("MODE: PHOTO CHALLENGE"))
        XCTAssertTrue(user.contains("WEATHER: light rain, 11°C"))
        XCTAssertFalse(user.contains("51.5"), "Coordinates are never sent")
        XCTAssertEqual(QuestPrompts.system(for: makeContext()), QuestPrompts.generationSystem)
    }

    func testTimeTrialLineAndPhotoTip() {
        var context = makeContext()
        context.timeTrial = true
        XCTAssertTrue(QuestPrompts.generationUser(context).contains("TIME TRIAL"))
        var quest = makeQuest()
        quest.isPhotoChallenge = true
        XCTAssertTrue(QuestPrompts.verificationUser(quest: quest, criteria: ["a"]).contains("photography tip"))
        XCTAssertFalse(QuestPrompts.verificationUser(quest: makeQuest(), criteria: ["a"]).contains("photography tip"))
    }

    func testHardPhotoChallengesNeedConstraintsNotCounts() {
        let photo = makeQuest(description: "Street photography by the castle with an umbrella, from a low angle.",
                              successCriteria: ["An umbrella is visible", "The castle is recognisable", "The photo is taken from a low angle"],
                              difficulty: 4)
        XCTAssertEqual(DifficultyValidator.validate(photo, requested: .hard, mode: .photo), [])
        XCTAssertFalse(DifficultyValidator.validate(photo, requested: .hard, mode: .quest).isEmpty, "Quests still need a count")
    }

    func testDemoPhotoModeOnlyGivesPhotoChallengesAndRespectsWeather() async throws {
        let mock = MockAIProvider(latencySeconds: 0)
        var rainy = makeContext(difficulty: .hard)
        rainy.mode = .photo
        rainy.weather = WeatherSnapshot(temperatureC: 11, weatherCode: 63, precipitationMM: 2, cloudCover: 100, windKmh: 10,
                                        isDay: true, sunrise: "07:18", sunset: "16:11", observedAt: "12:00")
        var titles = Set<String>()
        for _ in 0..<20 {
            let quest = try await mock.generateQuest(context: rainy)
            XCTAssertTrue(quest.isPhotoChallenge)
            XCTAssertGreaterThanOrEqual(quest.difficulty, 4)
            XCTAssertEqual(QuestRulesValidator.validate(quest, context: rainy), [], quest.title)
            titles.insert(quest.title)
        }
        XCTAssertFalse(titles.contains("Long Shadows"), "No sunny-day challenges in the rain")
        XCTAssertTrue(titles.contains("Umbrella Street") || titles.contains("Puddle Mirror"))
    }
}

@MainActor
final class TimeTrialFlowTests: XCTestCase {
    func testBeatingTheClockEarnsTheBonus() async throws {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.providerKind = .demo
        settings.scope = .venue
        settings.venueDescription = "Test Hack"
        settings.difficulty = .easy
        settings.timeTrial = true
        settings.mode = .photo
        settings.mockVerdictMode = .pass
        let container = try ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ProgressStore(context: container.mainContext)
        let flow = QuestFlowModel(settings: settings, tracker: AIUsageTracker(defaults: defaults), location: LocationService(),
                                  store: store, defaults: defaults)

        flow.requestQuest()
        try await waitFor { flow.phase == .offered }
        let active = try XCTUnwrap(flow.activeQuest)
        XCTAssertTrue(active.quest.isPhotoChallenge)
        XCTAssertNotNil(active.timeLimitSeconds)
        XCTAssertNil(active.deadline, "The clock only starts on accept")

        flow.accept()
        XCTAssertNotNil(flow.activeQuest?.deadline)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.black.setFill(); ctx.fill(CGRect(x: 40, y: 40, width: 80, height: 80))
        }
        for i in 0..<(active.quest.photoCount) {
            flow.submitPhoto(i == 0 ? image : UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { ctx in
                UIColor(hue: CGFloat(i) / 5, saturation: 1, brightness: 1, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
                UIColor.white.setFill(); ctx.fill(CGRect(x: CGFloat(i * 50), y: 20, width: 60, height: 120))
            })
        }
        try await waitFor { flow.outcome != nil || flow.phase == .reviewing }
        if flow.phase == .reviewing { flow.confirmReviewedPhoto() }
        try await waitFor { flow.outcome != nil }
        let outcome = try XCTUnwrap(flow.outcome)
        XCTAssertGreaterThan(outcome.timeBonus, 0)
        XCTAssertEqual(store.records().first?.beatClock, true)
        XCTAssertEqual(store.records().first?.isPhotoChallenge, true)
    }

    private func waitFor(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

final class IdentityRuleTests: XCTestCase {
    func testRecognisableLandmarksAreFineButPeopleAreNot() {
        let context = SafetyValidator.Context(scope: .city, isNightTime: false, allowPeople: true)
        let landmark = makeQuest(successCriteria: ["The castle is recognisable", "An umbrella is visible"])
        XCTAssertEqual(SafetyValidator.validate(landmark, context: context), [])
        for criterion in ["The person is recognisable", "You can recognise the hacker", "Identify the person by their badge"] {
            let quest = makeQuest(successCriteria: [criterion, "A laptop is visible"], involvesPeople: true)
            XCTAssertFalse(SafetyValidator.validate(quest, context: context).isEmpty, criterion)
        }
    }
}
