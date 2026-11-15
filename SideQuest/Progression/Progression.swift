import Foundation

/// Points, XP and levels. Pure functions so they're easy to test.
enum Scoring {
    /// Points it costs to reroll a quest. Rerolls are unlimited; points never go below zero.
    static let rerollCost = 5
    static let basePointsRange = 5...50

    /// Points × difficulty. The AI's points are clamped so a generous model can't inflate scores.
    /// The award is the same whichever path (free or optional purchase) the player took.
    static func award(points: Int, difficulty: Int) -> Int {
        let base = min(max(points, basePointsRange.lowerBound), basePointsRange.upperBound)
        let multiplier = min(max(difficulty, 1), 5)
        return base * multiplier
    }

    static func pointsAfterReroll(_ points: Int) -> Int { max(0, points - rerollCost) }

    /// Total XP needed to reach `level` (level 1 needs 0): 0, 100, 300, 600, 1000, …
    static func xpRequired(forLevel level: Int) -> Int {
        let n = max(1, level)
        return 50 * n * (n - 1)
    }

    static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpRequired(forLevel: level + 1) <= xp { level += 1 }
        return level
    }

    /// Progress within the current level, 0...1.
    static func levelProgress(xp: Int) -> (level: Int, intoLevel: Int, levelSize: Int, fraction: Double) {
        let level = level(forXP: xp)
        let start = xpRequired(forLevel: level)
        let size = xpRequired(forLevel: level + 1) - start
        let into = xp - start
        return (level, into, size, size > 0 ? Double(into) / Double(size) : 0)
    }

    static func title(forLevel level: Int) -> String {
        switch level {
        case 1: return "Curious Wanderer"
        case 2: return "Detourist"
        case 3: return "Trail Finder"
        case 4: return "Seasoned Scout"
        case 5: return "Quest Knight"
        case 6...7: return "Legend of the Lanes"
        default: return "Mythic Adventurer"
        }
    }
}

/// Daily streak: completing a quest on consecutive calendar days.
enum Streak {
    /// Streak after a completion on `date`.
    static func updated(current: Int, lastCompletionDay: Date?, completionDate: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastCompletionDay else { return 1 }
        let lastDay = calendar.startOfDay(for: last)
        let today = calendar.startOfDay(for: completionDate)
        let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        switch days {
        case ..<1: return max(current, 1)   // same day (or clock went backwards)
        case 1: return current + 1           // consecutive day
        default: return 1                    // streak broken
        }
    }

    /// The streak to display now: it lapses if the last completion was before yesterday.
    static func displayed(current: Int, lastCompletionDay: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let last = lastCompletionDay else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return days <= 1 ? current : 0
    }
}

enum Badge: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstQuest, hatTrick, tenQuests, onFire, allScopes, hardMode, renaissance, levelFive, shutterbug, speedDemon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstQuest: return "First Steps"
        case .hatTrick: return "Hat Trick"
        case .tenQuests: return "Questaholic"
        case .onFire: return "On Fire"
        case .allScopes: return "Globetrotter"
        case .hardMode: return "Hard Mode"
        case .renaissance: return "Renaissance"
        case .levelFive: return "Quest Knight"
        case .shutterbug: return "Shutterbug"
        case .speedDemon: return "Speed Demon"
        }
    }

    var detail: String {
        switch self {
        case .firstQuest: return "Complete your first quest"
        case .hatTrick: return "Complete 3 quests"
        case .tenQuests: return "Complete 10 quests"
        case .onFire: return "Reach a 3-day streak"
        case .allScopes: return "Complete a Venue, Nearby and City quest"
        case .hardMode: return "Complete a difficulty 5 quest"
        case .renaissance: return "Complete a quest in every theme"
        case .levelFive: return "Reach level 5"
        case .shutterbug: return "Complete 3 photo challenges"
        case .speedDemon: return "Beat the clock 3 times"
        }
    }

    var symbol: String {
        switch self {
        case .firstQuest: return "shoeprints.fill"
        case .hatTrick: return "3.circle.fill"
        case .tenQuests: return "star.circle.fill"
        case .onFire: return "flame.fill"
        case .allScopes: return "globe.europe.africa.fill"
        case .hardMode: return "bolt.shield.fill"
        case .renaissance: return "paintpalette.fill"
        case .levelFive: return "crown.fill"
        case .shutterbug: return "camera.aperture"
        case .speedDemon: return "stopwatch.fill"
        }
    }
}

/// Summary of play history used to award badges.
struct PlayerStats: Equatable, Sendable {
    var completedCount = 0
    var scopes: Set<QuestScope> = []
    var themes: Set<QuestTheme> = []
    var maxDifficulty = 0
    var streak = 0
    var level = 1
    var photoChallenges = 0
    var clockBeats = 0
}

enum BadgeEngine {
    static func earned(_ stats: PlayerStats) -> Set<Badge> {
        var badges: Set<Badge> = []
        if stats.completedCount >= 1 { badges.insert(.firstQuest) }
        if stats.completedCount >= 3 { badges.insert(.hatTrick) }
        if stats.completedCount >= 10 { badges.insert(.tenQuests) }
        if stats.streak >= 3 { badges.insert(.onFire) }
        if stats.scopes.isSuperset(of: Set(QuestScope.allCases)) { badges.insert(.allScopes) }
        if stats.maxDifficulty >= 5 { badges.insert(.hardMode) }
        if stats.themes.isSuperset(of: Set(QuestTheme.allCases)) { badges.insert(.renaissance) }
        if stats.level >= 5 { badges.insert(.levelFive) }
        if stats.photoChallenges >= 3 { badges.insert(.shutterbug) }
        if stats.clockBeats >= 3 { badges.insert(.speedDemon) }
        return badges
    }
}

/// Result of completing a quest, for the celebration screen.
struct CompletionOutcome: Equatable, Sendable {
    /// Total points, including any time trial bonus.
    var pointsAwarded: Int
    /// The part of `pointsAwarded` earned by beating the clock.
    var timeBonus: Int = 0
    var totalPoints: Int
    var xp: Int
    var previousLevel: Int
    var newLevel: Int
    var streak: Int
    var newBadges: [Badge]

    var leveledUp: Bool { newLevel > previousLevel }
}

/// Photo checks per quest. The first ones are free; after that the player can buy another try with
/// points, and each extra try costs more than the last.
enum Tries {
    /// Free photo checks per quest: the first go plus one retry.
    static let free = 2

    /// Points for extra try `number` (1 = the first one bought): 10% of the quest's award, doubling
    /// each time, rounded up to 5 and always at least 5 more than the one before.
    /// A 90-point quest costs 10, 20, 40, 75…; a 250-point one 25, 50, 100, 200…
    static func price(forExtraTry number: Int, award: Int) -> Int {
        let n = min(max(number, 1), 30)
        let raw = Double(max(award, 0)) * 0.1 * pow(2, Double(n - 1))
        let rounded = Int((raw / 5).rounded(.up)) * 5
        return max(rounded, 5 * n)
    }
}

/// Time trial: the countdown depends on difficulty and how far away the target is.
enum TimeTrial {
    /// Beating the clock earns +50%. Running out of time just means no bonus.
    static let bonusMultiplier = 1.5

    /// Minutes to find or set up the shot once you're there, by difficulty.
    static func searchMinutes(difficulty: Int) -> Double {
        switch min(max(difficulty, 1), 5) {
        case 1: return 3
        case 2: return 5
        case 3: return 8
        case 4: return 13
        default: return 20
        }
    }

    /// Walking pace (~4.5 km/h) for the first 2 km, then bus/bike pace (~15 km/h), plus 25% because
    /// routes aren't straight lines.
    static func travelMinutes(distanceMeters: Double) -> Double {
        let walk = min(distanceMeters, 2_000) / 75
        let ride = max(0, distanceMeters - 2_000) / 250
        return (walk + ride) * 1.25
    }

    /// Distance assumed when the quest has no specific target ("any").
    static func typicalDistance(for scope: QuestScope) -> Double {
        switch scope {
        case .venue: return 80
        case .nearby: return 150
        case .city: return 600
        }
    }

    /// The countdown in seconds, 2–120 minutes, rounded up to whole minutes.
    static func limit(difficulty: Int, distanceMeters: Double?, scope: QuestScope, photoCount: Int = 1) -> TimeInterval {
        let extraPhotos = Double(max(0, photoCount - 1))
        let search = searchMinutes(difficulty: difficulty) * (1 + 0.5 * extraPhotos)
        let travel = travelMinutes(distanceMeters: distanceMeters ?? typicalDistance(for: scope))
        let minutes = min(max((search + travel).rounded(.up), 2), 120)
        return minutes * 60
    }

    static func bonus(for award: Int) -> Int { Int((Double(award) * (bonusMultiplier - 1)).rounded()) }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3_600 ? String(format: "%d:%02d:%02d", s / 3_600, s % 3_600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
