import Foundation
@testable import SideQuest

/// A quest that passes every rule (money off, daytime, Nearby scope with "any" target).
func makeQuest(
    title: String = "Door Collector",
    description: String = "Find the most colourful front door within a few streets and photograph it straight on.",
    targetPlace: String = "any",
    successCriteria: [String] = ["A door is the main subject", "The door is brightly coloured"],
    photoInstructions: String = "Stand on the pavement opposite and shoot it straight on.",
    difficulty: Int = 2,
    points: Int = 20,
    estimatedTimeMinutes: Int = 15,
    requiresPurchase: Bool = false,
    optionalCostEstimate: Double = 0,
    freePath: String = "Wander nearby streets and photograph a door from the pavement.",
    safetyNotes: String = "Stay on public pavements.",
    involvesPeople: Bool = false,
    photoCount: Int = 1
) -> Quest {
    Quest(title: title, description: description, targetPlace: targetPlace, successCriteria: successCriteria,
          photoInstructions: photoInstructions, difficulty: difficulty, points: points,
          estimatedTimeMinutes: estimatedTimeMinutes, requiresPurchase: requiresPurchase,
          optionalCostEstimate: optionalCostEstimate, freePath: freePath, safetyNotes: safetyNotes,
          involvesPeople: involvesPeople, photoCount: photoCount)
}

let samplePlaces: [Place] = [
    Place(name: "The British Museum", category: "museum", distanceMeters: 420, coordinate: GeoPoint(latitude: 51.519413, longitude: -0.126957)),
    Place(name: "Gail's Bakery", category: "bakery", distanceMeters: 180, coordinate: GeoPoint(latitude: 51.5181, longitude: -0.1240)),
    Place(name: "Russell Square", category: "park", distanceMeters: 610, coordinate: GeoPoint(latitude: 51.5217, longitude: -0.1258)),
]

/// Noon on a weekday in London.
let daytime: Date = {
    var components = DateComponents(year: 2026, month: 11, day: 12, hour: 12, minute: 0)
    components.timeZone = TimeZone(identifier: "Europe/London")
    return Calendar(identifier: .gregorian).date(from: components)!
}()

/// 22:30 in London.
let nighttime: Date = {
    var components = DateComponents(year: 2026, month: 11, day: 12, hour: 22, minute: 30)
    components.timeZone = TimeZone(identifier: "Europe/London")
    return Calendar(identifier: .gregorian).date(from: components)!
}()

func makeContext(scope: QuestScope = .nearby, money: MoneySettings = .default, places: [Place] = samplePlaces,
                 venue: VenueContext? = nil, now: Date = daytime, difficulty: DifficultyPreference = .any,
                 allowPeople: Bool = false) -> QuestContext {
    QuestContext(scope: scope, theme: nil, difficulty: difficulty, money: money, allowPeople: allowPeople,
                 venueDescription: venue == nil ? nil : "Test Hack",
                 venue: venue, places: scope == .venue ? [] : places, areaName: "Bloomsbury", now: now,
                 timeZone: TimeZone(identifier: "Europe/London")!)
}

let sampleVenue = VenueContext(
    venueName: "HackLondon at Imperial College",
    summary: "A student hackathon in the Sherfield Building.",
    areas: [.init(name: "Great Hall", description: "Main hacking space."),
            .init(name: "Queen's Lawn", description: "Outdoor lawn."),
            .init(name: "Food court", description: "Snacks.")],
    typicalThings: ["stickers"], eventsAndHighlights: [], sponsors: ["Acme"], rulesAndEtiquette: [])

func questJSON(_ overrides: [String: Any] = [:], removing: [String] = []) -> Data {
    var object: [String: Any] = [
        "title": "Door Collector",
        "description": "Find a colourful door.",
        "target_place": "any",
        "success_criteria": ["A door is visible", "It is colourful"],
        "photo_instructions": "Shoot it straight on.",
        "difficulty": 2,
        "points": 20,
        "estimated_time_minutes": 15,
        "requires_purchase": false,
        "optional_cost_estimate": 0,
        "free_path": "Walk around and photograph a door.",
        "safety_notes": "Stay on the pavement.",
        "involves_people": false,
        "photo_count": 1,
    ]
    for (key, value) in overrides { object[key] = value }
    for key in removing { object.removeValue(forKey: key) }
    return try! JSONSerialization.data(withJSONObject: object)
}
