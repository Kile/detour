import Foundation

/// One reason a generated quest was rejected. Messages are fed back to the AI on the retry.
struct QuestViolation: Equatable, Sendable, CustomStringConvertible {
    enum Rule: String, Sendable {
        case json, place, money, safety, difficulty, proof
    }

    var rule: Rule
    var message: String

    var description: String { "[\(rule.rawValue)] \(message)" }
}

/// Regex-based phrase rules with simple negation awareness ("don't climb the fence" is fine,
/// "climb the fence" is not).
struct PhraseRule: Sendable {
    let id: String
    let message: String
    let regex: NSRegularExpression
    /// When true, a match inside a negated clause ("avoid…", "don't…", "no…") is ignored.
    let negationAware: Bool

    init(_ id: String, _ pattern: String, message: String, negationAware: Bool = true) {
        self.id = id
        self.message = message
        self.negationAware = negationAware
        // Patterns are compile-time constants; a typo should fail loudly in tests.
        self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Returns the matched phrase if the rule is violated by `text`.
    func firstViolation(in text: String) -> String? {
        // Without negation handling there's no need to split into clauses, and matching the whole
        // text keeps amounts like "£3.50" and longer phrases intact.
        guard negationAware else {
            let normalized = TextRules.normalize(text)
            guard let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let r = Range(match.range, in: normalized) else { return nil }
            return String(normalized[r])
        }
        for clause in TextRules.clauses(of: text) {
            let range = NSRange(clause.startIndex..., in: clause)
            guard let match = regex.firstMatch(in: clause, range: range) else { continue }
            if negationAware && TextRules.isNegated(clause) { continue }
            if let r = Range(match.range, in: clause) { return String(clause[r]) }
            return clause
        }
        return nil
    }
}

enum TextRules {
    /// Normalises curly quotes so patterns only need straight apostrophes.
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    /// Splits text into clauses on sentence punctuation, semicolons, commas and dashes.
    static func clauses(of text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet(charactersIn: ".!?;,\n—–()"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let negation = try! NSRegularExpression(
        pattern: #"\b(don't|do not|dont|never|avoid|avoiding|no|not|without|stay out|keep out|stay away|away from|isn't|aren't|nobody|nothing|respect|skip)\b"#,
        options: [.caseInsensitive])

    static func isNegated(_ clause: String) -> Bool {
        negation.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)) != nil
    }

    /// Lowercased, diacritic-free, punctuation-free, without a leading "the".
    static func normalizedName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var result = String(cleaned).split(separator: " ").joined(separator: " ")
        if result.hasPrefix("the ") { result.removeFirst(4) }
        return result
    }
}
