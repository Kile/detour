import Foundation

/// Checks that `target_place` is a place we actually gave the AI (or "any").
enum PlaceValidator {
    static func violation(targetPlace: String, allowed: [String]) -> QuestViolation? {
        let target = TextRules.normalizedName(targetPlace)
        if target == "any" || target.isEmpty && targetPlace.lowercased().contains("any") { return nil }
        if matches(targetPlace, allowed: allowed) != nil { return nil }
        let list = allowed.isEmpty ? "no specific places are available, so use \"any\"" :
            "use exactly one of: \(allowed.prefix(30).joined(separator: "; ")), or \"any\""
        return QuestViolation(rule: .place, message: "target_place \"\(targetPlace)\" is not a provided place — \(list)")
    }

    /// Returns the allowed name that `name` refers to, tolerating case, "the", punctuation
    /// and small additions ("British Museum" vs "The British Museum, Bloomsbury").
    static func matches(_ name: String, allowed: [String]) -> String? {
        let target = TextRules.normalizedName(name)
        guard !target.isEmpty else { return nil }
        for candidate in allowed {
            let normalized = TextRules.normalizedName(candidate)
            guard !normalized.isEmpty else { continue }
            if normalized == target { return candidate }
            let (short, long) = normalized.count < target.count ? (normalized, target) : (target, normalized)
            if short.count >= 5 && long.contains(short) { return candidate }
        }
        return nil
    }
}

/// Runs every rule on a generated quest. An empty result means the quest is OK to show.
enum QuestRulesValidator {
    static func validate(_ quest: Quest, context: QuestContext) -> [QuestViolation] {
        var violations = QuestJSON.structuralViolations(quest)
        if let place = PlaceValidator.violation(targetPlace: quest.targetPlace, allowed: context.allowedTargetPlaces) {
            violations.append(place)
        }
        violations += MoneyRulesValidator.validate(quest, settings: context.money)
        violations += SafetyValidator.validate(quest, context: .init(scope: context.scope, isNightTime: context.isNightTime,
                                                                      allowPeople: context.allowPeople))
        violations += DifficultyValidator.validate(quest, requested: context.difficulty, mode: context.mode)
        violations += ProofRulesValidator.validate(quest)
        return violations
    }
}

/// Keeps the photo proof fair: no demands for an empty frame (faces are blurred anyway, and busy
/// venues are never empty), and no "all in one photo" when the quest asks for several photos.
enum ProofRulesValidator {
    static let emptyFrameRule = PhraseRule(
        "empty-frame",
        #"\b(no (people|persons?|one|humans?|faces?|crowds?|strangers?|other people)( are| is)? (visible|in (the )?(shot|frame|photo|picture))|nobody (is )?(visible|in (the )?(shot|frame|photo))|without (any )?(people|persons|faces|anyone|humans)|keep (people|faces|anyone|everyone|strangers|others) out|(people|person)[- ]free|empty of people|free of people|no people)\b"#,
        message: "requires the photo to be free of people (people in the background are fine; faces are blurred automatically)",
        negationAware: false)

    static let singleFrameRule = PhraseRule(
        "single-frame",
        #"\b(in (one|the same|a single) (photo|shot|frame|picture|image)|single (photo|shot|frame|picture)|same (photo|shot|frame|picture)|all in frame|fit (them |it )?all in)\b"#,
        message: "says everything must be in one photo, but photo_count is more than 1 (one photo per find)",
        negationAware: false)

    static func validate(_ quest: Quest) -> [QuestViolation] {
        var violations: [QuestViolation] = []
        let proofFields = quest.successCriteria.map { ("success_criteria", $0) } + [("photo_instructions", quest.photoInstructions)]
        for (name, text) in proofFields {
            if let hit = emptyFrameRule.firstViolation(in: text) {
                violations.append(QuestViolation(rule: .proof, message: "\(name) \(emptyFrameRule.message) (\"\(hit)\")"))
            }
        }
        if quest.photoCount > 1 {
            for (name, text) in proofFields + [("description", quest.description)] {
                if let hit = singleFrameRule.firstViolation(in: text) {
                    violations.append(QuestViolation(rule: .proof, message: "\(name) \(singleFrameRule.message) (\"\(hit)\")"))
                }
            }
        }
        return violations
    }
}

/// Keeps "hard" honest: the difficulty must match what the player asked for, and hard quests
/// must actually be demanding (several criteria, at least one with a count or precise detail).
enum DifficultyValidator {
    private static let specificity = try! NSRegularExpression(
        pattern: #"\b(\d+|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|dozen|at least|at most|exactly|different|distinct|every|all|each|both|older than|before \d{4})\b"#,
        options: [.caseInsensitive])

    static func validate(_ quest: Quest, requested: DifficultyPreference, mode: QuestMode = .quest) -> [QuestViolation] {
        var violations: [QuestViolation] = []
        let range = requested.range
        if !range.contains(quest.difficulty) {
            let wanted = range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
            violations.append(QuestViolation(rule: .difficulty,
                message: "difficulty is \(quest.difficulty) but the player asked for \(wanted) — write a quest that genuinely matches that difficulty"))
        }
        if quest.difficulty >= 4 {
            if quest.successCriteria.count < 3 {
                violations.append(QuestViolation(rule: .difficulty,
                    message: "a difficulty \(quest.difficulty) quest needs at least 3 success criteria"))
            }
            let hasSpecific = quest.successCriteria.contains { criterion in
                specificity.firstMatch(in: criterion, range: NSRange(criterion.startIndex..., in: criterion)) != nil
            }
            // Hard photo challenges are demanding through combined constraints (place + subject +
            // light + technique) rather than counts.
            if !hasSpecific && mode == .quest {
                violations.append(QuestViolation(rule: .difficulty,
                    message: "a difficulty \(quest.difficulty) quest needs at least one criterion with a count or precise detail (e.g. \"at least 15 cans\", \"3 different logos\")"))
            }
        }
        return violations
    }
}

/// App-side leniency on top of the AI's verdict: give the benefit of the doubt.
enum VerdictPolicy {
    /// A "fail" below this confidence becomes "unsure".
    static let minimumFailConfidence = 0.6

    static func applyLeniency(_ verdict: Verdict) -> Verdict {
        var result = verdict
        let metCount = verdict.criteria.filter(\.met).count
        let total = max(1, verdict.criteria.count)
        switch verdict.verdict {
        case .fail:
            // Only fail when the photo clearly doesn't match.
            if verdict.confidence < minimumFailConfidence || Double(metCount) / Double(total) >= 0.5 {
                result.verdict = .unsure
            }
        case .unsure:
            if metCount == verdict.criteria.count && !verdict.criteria.isEmpty {
                result.verdict = .pass
            }
        case .pass:
            break
        }
        return result
    }
}
