import Foundation

enum QuestEngineError: LocalizedError, Equatable {
    /// Every attempt broke a rule (money, safety, places or JSON).
    case noValidQuest(lastViolations: [String])

    var errorDescription: String? {
        "The quest oracle is having an off moment — it couldn't come up with a quest that follows the rules. Tap to try again, or change the theme."
    }
}

/// Provider-agnostic generation: ask for a quest, validate it, feed problems back and regenerate.
/// At most `maxRetries` retries (3 attempts in total), then a friendly error.
struct QuestEngine {
    static let maxRetries = 2

    var provider: AIProvider
    /// Called after each rejected attempt (for the debug screen).
    var onRejected: @Sendable ([QuestViolation]) async -> Void = { _ in }

    struct Result: Equatable {
        var quest: Quest
        var attempts: Int
        var rejected: [[QuestViolation]]
    }

    func generate(context: QuestContext) async throws -> Result {
        var context = context
        var rejected: [[QuestViolation]] = []

        for attempt in 1...(Self.maxRetries + 1) {
            try Task.checkCancellation()
            let violations: [QuestViolation]
            do {
                let quest = try await provider.generateQuest(context: context)
                violations = QuestRulesValidator.validate(quest, context: context)
                if violations.isEmpty {
                    return Result(quest: quest, attempts: attempt, rejected: rejected)
                }
            } catch let error as AIJSONError {
                // Malformed JSON counts as a failed attempt, not a hard error.
                violations = [QuestViolation(rule: .json, message: error.errorDescription ?? "invalid JSON")]
            } catch AIError.truncated {
                violations = [QuestViolation(rule: .json, message: "the response was cut off; keep the quest short")]
            }
            rejected.append(violations)
            await onRejected(violations)
            context.rejectionFeedback = violations.map(\.message)
        }
        throw QuestEngineError.noValidQuest(lastViolations: rejected.last?.map(\.description) ?? [])
    }
}
