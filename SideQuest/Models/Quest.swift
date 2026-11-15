import Foundation

/// The quest exactly as the AI returns it (snake_case JSON). Every response is decoded with
/// `QuestJSON.decode`, which also checks types and ranges.
struct Quest: Codable, Equatable, Sendable {
    var title: String
    var description: String
    /// A provided place name, a researched venue area, or "any".
    var targetPlace: String
    /// Visually checkable statements.
    var successCriteria: [String]
    var photoInstructions: String
    /// 1–5
    var difficulty: Int
    var points: Int
    var estimatedTimeMinutes: Int
    /// Must always be false: every quest must be completable for free.
    var requiresPurchase: Bool
    /// GBP. Must be 0 when money is off, and never above the slider cap.
    var optionalCostEstimate: Double
    /// How to complete the quest without spending anything.
    var freePath: String
    var safetyNotes: String
    /// True when the quest needs the player to interact with other people (only allowed when
    /// the player has turned on people quests).
    var involvesPeople: Bool = false
    /// How many photos to take (1-4): one per find when the quest is about several separate things.
    var photoCount: Int = 1
    /// Set by the app (never by the AI): this is a photographer-mode challenge.
    var isPhotoChallenge: Bool = false

    enum CodingKeys: String, CodingKey {
        case title, description, difficulty, points
        case targetPlace = "target_place"
        case successCriteria = "success_criteria"
        case photoInstructions = "photo_instructions"
        case estimatedTimeMinutes = "estimated_time_minutes"
        case requiresPurchase = "requires_purchase"
        case optionalCostEstimate = "optional_cost_estimate"
        case freePath = "free_path"
        case safetyNotes = "safety_notes"
        case involvesPeople = "involves_people"
        case photoCount = "photo_count"
        case isPhotoChallenge = "is_photo_challenge"
    }

    init(title: String, description: String, targetPlace: String, successCriteria: [String], photoInstructions: String,
         difficulty: Int, points: Int, estimatedTimeMinutes: Int, requiresPurchase: Bool, optionalCostEstimate: Double,
         freePath: String, safetyNotes: String, involvesPeople: Bool = false, photoCount: Int = 1,
         isPhotoChallenge: Bool = false) {
        self.title = title
        self.description = description
        self.targetPlace = targetPlace
        self.successCriteria = successCriteria
        self.photoInstructions = photoInstructions
        self.difficulty = difficulty
        self.points = points
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.requiresPurchase = requiresPurchase
        self.optionalCostEstimate = optionalCostEstimate
        self.freePath = freePath
        self.safetyNotes = safetyNotes
        self.involvesPeople = involvesPeople
        self.photoCount = photoCount
        self.isPhotoChallenge = isPhotoChallenge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        targetPlace = try c.decode(String.self, forKey: .targetPlace)
        successCriteria = try c.decode([String].self, forKey: .successCriteria)
        photoInstructions = try c.decode(String.self, forKey: .photoInstructions)
        difficulty = try c.decode(Int.self, forKey: .difficulty)
        points = try c.decode(Int.self, forKey: .points)
        estimatedTimeMinutes = try c.decode(Int.self, forKey: .estimatedTimeMinutes)
        requiresPurchase = try c.decode(Bool.self, forKey: .requiresPurchase)
        optionalCostEstimate = try c.decode(Double.self, forKey: .optionalCostEstimate)
        freePath = try c.decode(String.self, forKey: .freePath)
        safetyNotes = try c.decode(String.self, forKey: .safetyNotes)
        // Optional so quests saved by earlier versions still load.
        involvesPeople = try c.decodeIfPresent(Bool.self, forKey: .involvesPeople) ?? false
        photoCount = try c.decodeIfPresent(Int.self, forKey: .photoCount) ?? 1
        isPhotoChallenge = try c.decodeIfPresent(Bool.self, forKey: .isPhotoChallenge) ?? false
    }

    var targetsAnyPlace: Bool {
        targetPlace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "any"
    }

    var hasOptionalPurchase: Bool { optionalCostEstimate > 0 }

    /// All player-facing text, used by the validators.
    var allText: [String] {
        [title, description, photoInstructions, freePath, safetyNotes] + successCriteria
    }
}

/// A quest the player has been offered or accepted, plus the on-device data needed to check it.
struct ActiveQuest: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var quest: Quest
    var scope: QuestScope
    var theme: QuestTheme?
    var money: MoneySettings
    var createdAt = Date()
    var accepted = false
    /// Where the player was when the quest was generated (Nearby/City only).
    var origin: GeoPoint?
    /// Coordinate of the matched target place, if the quest names one.
    var targetCoordinate: GeoPoint?
    /// Geofence radius in metres around `targetCoordinate` (or `origin` when the target is "any").
    var radiusMeters: Double?
    var venueName: String?
    var usageSessionID = UUID()
    /// The settings this quest was generated with.
    var fingerprint: QuestSettingsFingerprint?
    /// Weather when a photo challenge was made (Nearby/City only).
    var weather: WeatherSnapshot?
    /// Time trial: the countdown length, set when the quest is made; the clock starts on accept.
    var timeLimitSeconds: Double?
    var acceptedAt: Date?
    /// Photo checks used so far, and extra tries bought with points (see `Tries`).
    /// Optional so quests saved by older versions still load.
    var checksUsed: Int?
    var extraTriesBought: Int?

    var triesLeft: Int { max(0, Tries.free + (extraTriesBought ?? 0) - (checksUsed ?? 0)) }
    /// What the next extra try would cost.
    var nextTryPrice: Int {
        Tries.price(forExtraTry: (extraTriesBought ?? 0) + 1,
                    award: Scoring.award(points: quest.points, difficulty: quest.difficulty))
    }

    var isTimeTrial: Bool { timeLimitSeconds != nil }
    var deadline: Date? {
        guard let limit = timeLimitSeconds, let start = acceptedAt else { return nil }
        return start.addingTimeInterval(limit)
    }

    var geofenceCenter: GeoPoint? { targetCoordinate ?? origin }
}
