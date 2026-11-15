import Foundation
import SwiftData

/// A completed quest in the history list.
@Model
final class QuestRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var targetPlace: String
    var scopeRaw: String
    var themeRaw: String?
    var difficulty: Int
    var pointsAwarded: Int
    var completedAt: Date
    var verdictRaw: String
    var feedback: String
    /// Perceptual hash of the accepted photo, to reject near-duplicates later.
    var photoHash: Int64
    /// Hashes of any further photos in a multi-photo quest.
    var extraPhotoHashes: [Int64] = []
    var isPhotoChallenge: Bool = false
    /// Completed within the time trial countdown.
    var beatClock: Bool = false
    @Attribute(.externalStorage) var thumbnail: Data?
    var aiCalls: Int
    var aiCostUSD: Double

    init(id: UUID, title: String, summary: String, targetPlace: String, scope: QuestScope, theme: QuestTheme?,
         difficulty: Int, pointsAwarded: Int, completedAt: Date, verdict: Verdict.Outcome, feedback: String,
         photoHash: UInt64, thumbnail: Data?, aiCalls: Int, aiCostUSD: Double) {
        self.id = id
        self.title = title
        self.summary = summary
        self.targetPlace = targetPlace
        self.scopeRaw = scope.rawValue
        self.themeRaw = theme?.rawValue
        self.difficulty = difficulty
        self.pointsAwarded = pointsAwarded
        self.completedAt = completedAt
        self.verdictRaw = verdict.rawValue
        self.feedback = feedback
        self.photoHash = Int64(bitPattern: photoHash)
        self.thumbnail = thumbnail
        self.aiCalls = aiCalls
        self.aiCostUSD = aiCostUSD
    }

    var scope: QuestScope { QuestScope(rawValue: scopeRaw) ?? .nearby }
    var theme: QuestTheme? { themeRaw.flatMap(QuestTheme.init(rawValue:)) }
    var hash: UInt64 { UInt64(bitPattern: photoHash) }
    var allHashes: [UInt64] { [hash] + extraPhotoHashes.map { UInt64(bitPattern: $0) } }
}

/// The player's running totals. There is exactly one.
@Model
final class PlayerProfile {
    var points: Int
    var xp: Int
    var streak: Int
    var bestStreak: Int
    var lastCompletionDay: Date?
    var rerolls: Int
    var badgeIDs: [String]

    init() {
        points = 0
        xp = 0
        streak = 0
        bestStreak = 0
        lastCompletionDay = nil
        rerolls = 0
        badgeIDs = []
    }

    var badges: Set<Badge> { Set(badgeIDs.compactMap(Badge.init(rawValue:))) }
    var level: Int { Scoring.level(forXP: xp) }
}

/// Venue research is cached so web searches (which cost extra) run once per venue.
@Model
final class CachedVenue {
    @Attribute(.unique) var key: String
    var input: String
    var contextJSON: Data
    var researchedAt: Date

    init(key: String, input: String, contextJSON: Data, researchedAt: Date = Date()) {
        self.key = key
        self.input = input
        self.contextJSON = contextJSON
        self.researchedAt = researchedAt
    }

    var context: VenueContext? { try? JSONDecoder().decode(VenueContext.self, from: contextJSON) }
}

enum PersistenceSchema {
    static let models: [any PersistentModel.Type] = [QuestRecord.self, PlayerProfile.self, CachedVenue.self]
}
