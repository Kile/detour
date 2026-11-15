import Foundation
import Observation

/// Debug counter of AI calls and estimated cost, per quest and in total.
@MainActor
@Observable
final class AIUsageTracker {
    private(set) var calls: [AICallRecord] = []
    /// Calls belonging to the current quest (from the first tap through rerolls to completion).
    private(set) var currentQuestCalls: [AICallRecord] = []
    private(set) var lastRejections: [String] = []

    private let defaults: UserDefaults
    private(set) var lifetimeCalls: Int
    private(set) var lifetimeCostUSD: Double

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lifetimeCalls = defaults.integer(forKey: "usage.lifetimeCalls")
        lifetimeCostUSD = defaults.double(forKey: "usage.lifetimeCost")
    }

    func record(_ call: AICallRecord) {
        calls.append(call)
        if calls.count > 200 { calls.removeFirst(calls.count - 200) }
        currentQuestCalls.append(call)
        lifetimeCalls += 1
        lifetimeCostUSD += call.costUSD
        defaults.set(lifetimeCalls, forKey: "usage.lifetimeCalls")
        defaults.set(lifetimeCostUSD, forKey: "usage.lifetimeCost")
    }

    func recordRejection(_ violations: [QuestViolation]) {
        lastRejections = violations.map(\.description)
    }

    func startNewQuest() {
        currentQuestCalls = []
        lastRejections = []
    }

    var currentQuestCost: Double { currentQuestCalls.reduce(0) { $0 + $1.costUSD } }

    var sink: AIUsageSink {
        { [weak self] call in await self?.record(call) }
    }

    func resetLifetime() {
        lifetimeCalls = 0
        lifetimeCostUSD = 0
        calls = []
        defaults.removeObject(forKey: "usage.lifetimeCalls")
        defaults.removeObject(forKey: "usage.lifetimeCost")
    }

    static func formatCost(_ usd: Double) -> String {
        usd == 0 ? "$0" : (usd < 0.01 ? String(format: "$%.4f", usd) : String(format: "$%.3f", usd))
    }
}
