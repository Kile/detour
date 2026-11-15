#if DEBUG
import UIKit

/// Debug builds only: when launched with `-marketing`, fill the (in-memory) store with a believable
/// play history so App Store / Devpost screenshots don't show an empty app. Never runs otherwise.
@MainActor
enum MarketingSeed {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-marketing") }

    /// Sample weather for screenshots (`-mockWeather rain|sun|night`), like demo mode's sample quests.
    static var weatherOverride: WeatherSnapshot? {
        switch UserDefaults.standard.string(forKey: "mockWeather") {
        case "rain": return WeatherSnapshot(temperatureC: 11, weatherCode: 61, precipitationMM: 0.8, cloudCover: 100, windKmh: 14,
                                            isDay: true, sunrise: "07:18", sunset: "16:11", observedAt: "13:05")
        case "sun": return WeatherSnapshot(temperatureC: 16, weatherCode: 0, precipitationMM: 0, cloudCover: 5, windKmh: 8,
                                           isDay: true, sunrise: "07:18", sunset: "16:11", observedAt: "15:30")
        case "night": return WeatherSnapshot(temperatureC: 8, weatherCode: 2, precipitationMM: 0, cloudCover: 40, windKmh: 6,
                                             isDay: false, sunrise: "07:18", sunset: "16:11", observedAt: "19:40")
        default: return nil
        }
    }

    /// A fixed real place for screenshots (`-mockPlace "Royal Opera House|51.5129|-0.1222|theatre"`), added to the
    /// nearby places so the demo quest and map pin don't depend on whatever Apple Maps returns that day.
    static func placeOverride(near here: GeoPoint) -> Place? {
        guard let raw = UserDefaults.standard.string(forKey: "mockPlace") else { return nil }
        let parts = raw.split(separator: "|").map(String.init)
        guard parts.count >= 3, let latitude = Double(parts[1]), let longitude = Double(parts[2]) else { return nil }
        let point = GeoPoint(latitude: latitude, longitude: longitude)
        return Place(name: parts[0], category: parts.count > 3 ? parts[3] : "landmark",
                     distanceMeters: Int(Geofence.distance(here, point).rounded()), coordinate: point)
    }

    static func apply(settings: AppSettings, store: ProgressStore) {
        guard isActive else { return }
        settings.showDebugInfo = false
        settings.skipGeofence = true
        settings.preferTestPhotos = true
        settings.mockVerdictMode = .pass

        let profile = store.profile()
        profile.points = 1_240
        profile.xp = 1_180          // level 5, "Quest Knight"
        profile.streak = 6
        profile.bestStreak = 9
        profile.lastCompletionDay = Date()
        profile.rerolls = 4
        profile.badgeIDs = [Badge.firstQuest, .hatTrick, .tenQuests, .onFire, .allScopes, .levelFive, .shutterbug, .speedDemon]
            .map(\.rawValue)

        let history: [(String, String, QuestScope, QuestTheme?, Int, Int, String, UIColor, Bool)] = [
            ("Antique Hunter", "Found a willow vase that looks at least 70 years old, price tag and all.", .nearby, .history, 3, 90, "🏺", .systemTeal, false),
            ("Puddle Mirror", "That reflection is gorgeous: the street lights doubled in the puddle.", .city, .creative, 4, 180, "🌧️", .systemIndigo, true),
            ("Sponsor Bingo", "Three different logos, all readable. Bingo!", .venue, .explore, 4, 160, "🏷️", .systemOrange, false),
            ("Monster Census", "Five empty cans and a very proud thumbs up.", .venue, .social, 5, 250, "🥫", .systemGreen, false),
            ("Door Rainbow", "Red, blue, green and yellow: the full set.", .nearby, .creative, 5, 225, "🚪", .systemPink, true),
            ("Clock Collector", "Station, church and shopfront clocks: right on time.", .city, .history, 4, 180, "🕰️", .systemBrown, false),
            ("Green Machine", "Green fills the whole frame. Lovely and leafy.", .venue, .creative, 1, 15, "🌿", .systemMint, true),
        ]
        let calendar = Calendar.current
        for (index, item) in history.enumerated() {
            let date = calendar.date(byAdding: .hour, value: -(index * 9 + 1), to: Date()) ?? Date()
            let thumbnail = index == 0
                ? UIImage(named: "debug_test_pass.jpg").flatMap(ImageProcessor.thumbnail)
                : ImageProcessor.thumbnail(tile(emoji: item.6, color: item.7))
            let record = QuestRecord(
                id: UUID(), title: item.0, summary: item.1, targetPlace: "any", scope: item.2, theme: item.3,
                difficulty: item.4, pointsAwarded: item.5, completedAt: date, verdict: .pass, feedback: item.1,
                photoHash: UInt64.random(in: 1...UInt64.max), thumbnail: thumbnail, aiCalls: 2, aiCostUSD: 0.002)
            record.isPhotoChallenge = ["Puddle Mirror", "Green Machine"].contains(item.0)
            record.beatClock = item.8
            store.context.insert(record)
        }
        try? store.context.save()
    }

    /// A simple, colourful stand-in photo for the journal.
    private static func tile(emoji: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 360, height: 360)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0.45).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let text = emoji as NSString
            let font = UIFont.systemFont(ofSize: 190)
            let textSize = text.size(withAttributes: [.font: font])
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: [.font: font])
        }
    }
}
#endif
