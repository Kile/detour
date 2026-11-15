import Foundation

/// The verification result as returned by the AI (snake_case JSON).
struct Verdict: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, CaseIterable, Sendable {
        case pass, fail, unsure
    }

    struct Criterion: Codable, Equatable, Identifiable, Sendable {
        var criterion: String
        var met: Bool
        var reason: String
        var id: String { criterion }
    }

    var verdict: Outcome
    var criteria: [Criterion]
    /// 0...1
    var confidence: Double
    var feedback: String

    /// Set by the app (not the AI) when the result came from the stronger re-check model.
    var recheckedWithStrongerModel: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case verdict, criteria, confidence, feedback
        case recheckedWithStrongerModel = "rechecked_with_stronger_model"
    }
}
