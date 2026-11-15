import Foundation

enum AIJSONError: LocalizedError, Equatable {
    case notJSON
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "The AI response wasn't JSON."
        case .invalid(let reason): return "The AI response was invalid: \(reason)"
        }
    }
}

/// Shared JSON helpers for every AI response, whatever the provider.
enum AIJSON {
    /// Extracts the outermost JSON object from text, tolerating ```json fences and chatter.
    static func extractObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw AIJSONError.invalid("missing field \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, context) {
            throw AIJSONError.invalid("wrong type for \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"")
        } catch let DecodingError.valueNotFound(_, context) {
            throw AIJSONError.invalid("null value for \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"")
        } catch let DecodingError.dataCorrupted(context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw path.isEmpty ? AIJSONError.notJSON : AIJSONError.invalid("bad value for \"\(path)\"")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, fromText text: String) throws -> T {
        guard let data = extractObject(from: text) else { throw AIJSONError.notJSON }
        return try decode(type, from: data)
    }
}

/// Decodes and structurally validates quest JSON.
enum QuestJSON {
    static func decode(_ data: Data) throws -> Quest {
        let quest = try AIJSON.decode(Quest.self, from: data)
        let problems = structuralViolations(quest)
        if !problems.isEmpty {
            throw AIJSONError.invalid(problems.map(\.message).joined(separator: "; "))
        }
        return quest
    }

    static func decode(text: String) throws -> Quest {
        guard let data = AIJSON.extractObject(from: text) else { throw AIJSONError.notJSON }
        return try decode(data)
    }

    /// Type, range and presence checks that don't depend on context.
    static func structuralViolations(_ quest: Quest) -> [QuestViolation] {
        var issues: [String] = []
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if blank(quest.title) { issues.append("title is empty") }
        if quest.title.count > 80 { issues.append("title is longer than 80 characters") }
        if blank(quest.description) { issues.append("description is empty") }
        if quest.description.count > 700 { issues.append("description is longer than 700 characters") }
        if blank(quest.targetPlace) { issues.append("target_place is empty (use \"any\" if no specific place)") }
        if quest.successCriteria.isEmpty { issues.append("success_criteria is empty") }
        if quest.successCriteria.count > 6 { issues.append("success_criteria has more than 6 items") }
        if quest.successCriteria.contains(where: blank) { issues.append("success_criteria contains an empty item") }
        if blank(quest.photoInstructions) { issues.append("photo_instructions is empty") }
        if !(1...5).contains(quest.difficulty) { issues.append("difficulty must be 1-5") }
        if !(1...100).contains(quest.points) { issues.append("points must be 1-100") }
        if !(1...240).contains(quest.estimatedTimeMinutes) { issues.append("estimated_time_minutes must be 1-240") }
        if !(1...4).contains(quest.photoCount) { issues.append("photo_count must be 1-4") }
        if !quest.optionalCostEstimate.isFinite || quest.optionalCostEstimate < 0 {
            issues.append("optional_cost_estimate must be a number >= 0")
        }
        if quest.freePath.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            issues.append("free_path must describe how to complete the quest for free")
        }
        return issues.map { QuestViolation(rule: .json, message: $0) }
    }
}

/// Decodes verification JSON and normalises obviously-off values.
enum VerdictJSON {
    static func decode(_ data: Data) throws -> Verdict {
        var verdict = try AIJSON.decode(Verdict.self, from: data)
        verdict.recheckedWithStrongerModel = nil
        guard verdict.confidence.isFinite else { throw AIJSONError.invalid("confidence is not a number") }
        if verdict.confidence > 1, verdict.confidence <= 100 { verdict.confidence /= 100 }
        verdict.confidence = min(1, max(0, verdict.confidence))
        verdict.criteria = verdict.criteria.filter { !$0.criterion.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !verdict.criteria.isEmpty else { throw AIJSONError.invalid("criteria is empty") }
        if verdict.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            verdict.feedback = verdict.verdict == .fail ? "Not quite — give it another go!" : "Nice one!"
        }
        return verdict
    }

    static func decode(text: String) throws -> Verdict {
        guard let data = AIJSON.extractObject(from: text) else { throw AIJSONError.notJSON }
        return try decode(data)
    }
}

/// Decodes venue research JSON.
enum VenueJSON {
    static func decode(_ data: Data) throws -> VenueContext {
        var venue = try AIJSON.decode(VenueContext.self, from: data)
        venue.areas = venue.areas.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if venue.venueName.trimmingCharacters(in: .whitespaces).isEmpty {
            throw AIJSONError.invalid("venue_name is empty")
        }
        return venue
    }

    static func decode(text: String) throws -> VenueContext {
        guard let data = AIJSON.extractObject(from: text) else { throw AIJSONError.notJSON }
        return try decode(data)
    }
}
