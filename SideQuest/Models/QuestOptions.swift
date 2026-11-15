import Foundation

enum QuestScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case venue, nearby, city

    var id: String { rawValue }

    var title: String {
        switch self {
        case .venue: return "Venue"
        case .nearby: return "Nearby"
        case .city: return "City"
        }
    }

    var symbol: String {
        switch self {
        case .venue: return "building.2.fill"
        case .nearby: return "figure.walk"
        case .city: return "map.fill"
        }
    }

    var blurb: String {
        switch self {
        case .venue: return "Inside your event or building. No GPS needed."
        case .nearby: return "About 1 km on foot."
        case .city: return "Anywhere around town."
        }
    }

    var usesLocation: Bool { self != .venue }

    /// Search radius for places, in metres.
    var searchRadius: Double {
        switch self {
        case .venue: return 0
        case .nearby: return 1_000
        case .city: return 8_000
        }
    }
}

/// What kind of challenge the big button gives you.
enum QuestMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Find things and prove it with a photo.
    case quest
    /// Photographer mode: briefs about seeing and composing a good shot, using the current weather and light.
    case photo

    var id: String { rawValue }
    var title: String { self == .quest ? "Quests" : "Photo challenges" }
    var symbol: String { self == .quest ? "flag.fill" : "camera.aperture" }
    var buttonTitle: String { self == .quest ? "Give me\na quest" : "Give me a\nphoto challenge" }
    var accessibilityTitle: String { self == .quest ? "Give me a quest" : "Give me a photo challenge" }
}

enum QuestTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case social, creative, explore, food, history

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .social: return "👋"
        case .creative: return "🎨"
        case .explore: return "🧭"
        case .food: return "🥐"
        case .history: return "🏛️"
        }
    }

    /// Hints passed to the AI so the theme is interpreted consistently.
    var promptHint: String {
        switch self {
        case .social: return "social: friendly, chatting with people is welcome (but never photographing them)"
        case .creative: return "creative: art, colours, composition, playful photo ideas"
        case .explore: return "explore: discovering hidden corners, details and wayfinding"
        case .food: return "food: food culture, menus, markets, bakeries, snacks (photograph displays, not people)"
        case .history: return "history: plaques, old buildings, antiques, monuments, local stories"
        }
    }

    /// Natural-language MapKit queries that surface fitting places.
    var placeQueries: [String] {
        switch self {
        case .social: return ["library", "community centre", "park", "market"]
        case .creative: return ["art gallery", "street art", "bookshop", "craft shop"]
        case .explore: return ["park", "viewpoint", "garden", "landmark"]
        case .food: return ["bakery", "market", "cafe", "food hall"]
        case .history: return ["museum", "historic site", "antique shop", "monument"]
        }
    }
}

enum DifficultyPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case any, easy, medium, hard

    var id: String { rawValue }
    var title: String { self == .any ? "Any" : rawValue.capitalized }

    var range: ClosedRange<Int> {
        switch self {
        case .any: return 1...5
        case .easy: return 1...2
        case .medium: return 3...3
        case .hard: return 4...5
        }
    }
}

struct MoneySettings: Codable, Equatable, Sendable {
    /// When false, quests must never involve money in any way.
    var enabled: Bool
    /// Upper bound for any optional purchase, in GBP.
    var maxSpendGBP: Double

    static let `default` = MoneySettings(enabled: false, maxSpendGBP: 5)
    static let sliderRange: ClosedRange<Double> = 0...50

    /// The cap that actually applies: 0 whenever money is off.
    var effectiveCap: Double { enabled ? max(0, maxSpendGBP) : 0 }
}

struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// A real place found via MapKit. The coordinate stays on-device; only name, category and distance go to the AI.
struct Place: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var category: String
    var distanceMeters: Int
    var coordinate: GeoPoint

    var id: String { name }

    /// The line we send to the AI. No coordinates, ever.
    var promptLine: String {
        let rounded = max(50, Int((Double(distanceMeters) / 50).rounded()) * 50)
        let distance = rounded >= 1_000 ? String(format: "~%.1f km", Double(rounded) / 1_000) : "~\(rounded) m"
        return "\(name) (\(category), \(distance))"
    }
}

/// The settings a quest is generated with. Lets the quest card show when a reroll will use
/// different settings, and stops "discard" from being a free reroll.
struct QuestSettingsFingerprint: Codable, Equatable, Sendable {
    var scope: QuestScope
    var venue: String
    var theme: QuestTheme?
    var difficulty: DifficultyPreference
    var allowPeople: Bool
    var money: MoneySettings
    /// Optional so quests saved by earlier versions still load.
    var mode: QuestMode? = .quest
    var timeTrial: Bool? = false

    /// Short labels for the chips on the quest card.
    var labels: [String] {
        var items: [String] = []
        if mode == .photo { items.append("📷 Photo") }
        items.append(scope == .venue && !venue.isEmpty ? "\(scope.title): \(venue)" : scope.title)
        items.append(difficulty == .any ? "Any difficulty" : difficulty.title)
        items.append(theme.map { "\($0.emoji) \($0.title)" } ?? "🎲 Surprise")
        if allowPeople { items.append("👥 People") }
        if money.enabled { items.append("£\(Int(money.maxSpendGBP))") }
        if timeTrial == true { items.append("⏱ Time trial") }
        return items
    }

    /// What changed compared with an older quest's settings, e.g. ["Hard", "Nearby"].
    func changes(since other: QuestSettingsFingerprint) -> [String] {
        var changed: [String] = []
        if scope != other.scope || (scope == .venue && venue != other.venue) { changed.append(scope.title) }
        if difficulty != other.difficulty { changed.append(difficulty == .any ? "Any difficulty" : difficulty.title) }
        if theme != other.theme { changed.append(theme?.title ?? "Surprise") }
        if allowPeople != other.allowPeople { changed.append(allowPeople ? "People on" : "People off") }
        if money != other.money { changed.append(money.enabled ? "£\(Int(money.maxSpendGBP)) spend" : "No spending") }
        if (mode ?? .quest) != (other.mode ?? .quest) { changed.append((mode ?? .quest).title) }
        if (timeTrial ?? false) != (other.timeTrial ?? false) { changed.append(timeTrial == true ? "Time trial on" : "Time trial off") }
        return changed
    }
}
