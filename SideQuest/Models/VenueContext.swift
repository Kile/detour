import Foundation

/// What we know about a venue after web research. Cached per venue in SwiftData.
struct VenueContext: Codable, Equatable, Sendable {
    struct Area: Codable, Equatable, Identifiable, Sendable {
        var name: String
        var description: String
        var id: String { name }
    }

    var venueName: String
    var summary: String
    /// Rooms, halls, zones, floors. These are the only specific places a venue quest may target.
    var areas: [Area]
    /// Things you'd typically find there (signage, art, stands, snacks...).
    var typicalThings: [String]
    var eventsAndHighlights: [String]
    var sponsors: [String]
    /// Etiquette and no-go zones (staff-only areas, quiet rooms, talks in progress...).
    var rulesAndEtiquette: [String]

    /// Filled in by the app, not the AI.
    var sources: [String]? = nil
    var usedWebSearch: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case summary, areas, sponsors, sources
        case venueName = "venue_name"
        case typicalThings = "typical_things"
        case eventsAndHighlights = "events_and_highlights"
        case rulesAndEtiquette = "rules_and_etiquette"
        case usedWebSearch = "used_web_search"
    }

    var allowedTargets: [String] { [venueName] + areas.map(\.name) }
}
