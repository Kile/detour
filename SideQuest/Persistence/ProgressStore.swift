import Foundation
import SwiftData

/// Reads and writes progression, history and the venue cache.
@MainActor
final class ProgressStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func profile() -> PlayerProfile {
        if let existing = try? context.fetch(FetchDescriptor<PlayerProfile>()).first { return existing }
        let profile = PlayerProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    func records() -> [QuestRecord] {
        let descriptor = FetchDescriptor<QuestRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func recentTitles(limit: Int = 6) -> [String] {
        var descriptor = FetchDescriptor<QuestRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(\.title)
    }

    func acceptedPhotoHashes() -> [UInt64] { records().flatMap(\.allHashes) }

    /// Deducts the reroll cost (never below zero). Returns the new points total.
    @discardableResult
    func applyReroll() -> Int {
        let profile = profile()
        profile.points = Scoring.pointsAfterReroll(profile.points)
        profile.rerolls += 1
        try? context.save()
        return profile.points
    }

    /// Spends points if the player has enough. Returns false (and spends nothing) otherwise.
    @discardableResult
    func spend(_ amount: Int) -> Bool {
        let profile = profile()
        guard amount >= 0, profile.points >= amount else { return false }
        profile.points -= amount
        try? context.save()
        return true
    }

    /// Awards points/XP, updates the streak and badges, and saves the history entry.
    func complete(_ active: ActiveQuest, verdict: Verdict, photoHashes: [UInt64], thumbnail: Data?,
                  aiCalls: Int, aiCostUSD: Double, beatClock: Bool = false, now: Date = Date()) -> CompletionOutcome {
        let profile = profile()
        let previousLevel = profile.level
        let base = Scoring.award(points: active.quest.points, difficulty: active.quest.difficulty)
        let timeBonus = beatClock ? TimeTrial.bonus(for: base) : 0
        let awarded = base + timeBonus

        profile.points += awarded
        profile.xp += awarded
        profile.streak = Streak.updated(current: profile.streak, lastCompletionDay: profile.lastCompletionDay, completionDate: now)
        profile.bestStreak = max(profile.bestStreak, profile.streak)
        profile.lastCompletionDay = now

        let record = QuestRecord(
            id: active.id, title: active.quest.title, summary: active.quest.description,
            targetPlace: active.quest.targetPlace, scope: active.scope, theme: active.theme,
            difficulty: active.quest.difficulty, pointsAwarded: awarded, completedAt: now,
            verdict: verdict.verdict, feedback: verdict.feedback, photoHash: photoHashes.first ?? 0, thumbnail: thumbnail,
            aiCalls: aiCalls, aiCostUSD: aiCostUSD)
        record.extraPhotoHashes = photoHashes.dropFirst().map { Int64(bitPattern: $0) }
        record.isPhotoChallenge = active.quest.isPhotoChallenge
        record.beatClock = beatClock
        context.insert(record)

        let all = records() + (records().contains { $0.id == record.id } ? [] : [record])
        let stats = PlayerStats(
            completedCount: all.count,
            scopes: Set(all.map(\.scope)),
            themes: Set(all.compactMap(\.theme)),
            maxDifficulty: all.map(\.difficulty).max() ?? 0,
            streak: profile.streak,
            level: profile.level,
            photoChallenges: all.filter(\.isPhotoChallenge).count,
            clockBeats: all.filter(\.beatClock).count)
        let before = profile.badges
        let after = BadgeEngine.earned(stats).union(before)
        profile.badgeIDs = Badge.allCases.filter { after.contains($0) }.map(\.rawValue)
        try? context.save()

        return CompletionOutcome(
            pointsAwarded: awarded, timeBonus: timeBonus, totalPoints: profile.points, xp: profile.xp,
            previousLevel: previousLevel, newLevel: profile.level, streak: profile.streak,
            newBadges: Badge.allCases.filter { after.contains($0) && !before.contains($0) })
    }

    // MARK: Venue cache

    static func venueKey(_ description: String, provider: ProviderKind) -> String {
        provider.rawValue + ":" + TextRules.normalizedName(description)
    }

    func cachedVenue(_ description: String, provider: ProviderKind) -> VenueContext? {
        let key = Self.venueKey(description, provider: provider)
        let descriptor = FetchDescriptor<CachedVenue>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first?.context
    }

    func cacheVenue(_ venue: VenueContext, description: String, provider: ProviderKind) {
        let key = Self.venueKey(description, provider: provider)
        guard let data = try? JSONEncoder().encode(venue) else { return }
        let descriptor = FetchDescriptor<CachedVenue>(predicate: #Predicate { $0.key == key })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.contextJSON = data
            existing.researchedAt = Date()
        } else {
            context.insert(CachedVenue(key: key, input: description, contextJSON: data))
        }
        try? context.save()
    }

    func clearVenueCache() {
        try? context.delete(model: CachedVenue.self)
        try? context.save()
    }

    func resetProgress() {
        try? context.delete(model: QuestRecord.self)
        try? context.delete(model: PlayerProfile.self)
        try? context.save()
    }
}
