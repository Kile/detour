import Foundation

/// Everything the AI needs to write one quest. Contains place names but never coordinates.
struct QuestContext: Equatable, Sendable {
    var scope: QuestScope
    var theme: QuestTheme?
    var difficulty: DifficultyPreference
    var money: MoneySettings
    /// When true, quests may involve chatting with and getting help from other people.
    var allowPeople: Bool = false
    var mode: QuestMode = .quest
    /// Current weather at the player's location (photo challenges in Nearby/City).
    var weather: WeatherSnapshot? = nil
    var timeTrial: Bool = false
    /// The one-line venue description the user typed (Venue scope).
    var venueDescription: String?
    var venue: VenueContext?
    /// Real places from MapKit (Nearby/City scope).
    var places: [Place] = []
    /// Neighbourhood or city name from reverse geocoding (Nearby/City scope).
    var areaName: String?
    var now: Date = Date()
    var timeZone: TimeZone = .current
    var recentQuestTitles: [String] = []
    /// Why earlier attempts were rejected, so the next attempt can fix it.
    var rejectionFeedback: [String] = []

    /// The specific places a quest is allowed to target (besides "any").
    var allowedTargetPlaces: [String] {
        switch scope {
        case .venue: return venue?.allowedTargets ?? []
        case .nearby, .city:
            var names = places.map(\.name)
            if scope == .city, let areaName { names.append(areaName) }
            return names
        }
    }

    var localHour: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: now)
    }

    /// Darkness heuristic used by both the prompt and the safety validator.
    var isNightTime: Bool { localHour >= 20 || localHour < 6 }

    var localTimeDescription: String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEEE HH:mm"
        return formatter.string(from: now)
    }
}
