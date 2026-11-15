import Foundation

/// JSON schemas for structured output. Kept static so the API can cache their compiled grammar.
/// (Structured outputs don't support min/max constraints; ranges are enforced by the validators.)
enum QuestSchemas {
    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    static let quest: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "title", "description", "target_place", "success_criteria", "photo_instructions", "difficulty",
            "points", "estimated_time_minutes", "requires_purchase", "optional_cost_estimate", "free_path", "safety_notes",
            "involves_people", "photo_count",
        ],
        "properties": [
            "title": string("Short, playful title (max 6 words)."),
            "description": string("What to do, max 3 sentences."),
            "target_place": string("Exactly one name from ALLOWED PLACES, or \"any\"."),
            "success_criteria": [
                "type": "array",
                "description": "2-4 statements that can be checked just by looking at the photo.",
                "items": ["type": "string"],
            ],
            "photo_instructions": string("How to frame the photo(s). Proof must never depend on a face or identity; people in the background are fine."),
            "difficulty": ["type": "integer", "enum": [1, 2, 3, 4, 5]],
            "points": ["type": "integer", "description": "10-50, reflecting effort."],
            "estimated_time_minutes": ["type": "integer", "description": "5-60."],
            "requires_purchase": ["type": "boolean", "enum": [false], "description": "Always false."],
            "optional_cost_estimate": ["type": "number", "description": "GBP; 0 when there is no optional purchase."],
            "free_path": string("How to complete the quest without spending anything."),
            "safety_notes": string("One short, practical safety sentence."),
            "involves_people": ["type": "boolean", "description": "True if the quest needs anyone else's help or involvement."],
            "photo_count": ["type": "integer", "enum": [1, 2, 3, 4],
                            "description": "Photos to take: one per find when finding several separate things; 1 when they appear together."],
        ],
    ]

    static let verdict: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["verdict", "criteria", "confidence", "feedback"],
        "properties": [
            "verdict": ["type": "string", "enum": ["pass", "fail", "unsure"]],
            "criteria": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["criterion", "met", "reason"],
                    "properties": [
                        "criterion": string("The criterion text, copied exactly."),
                        "met": ["type": "boolean"],
                        "reason": string("Short reason based on visible evidence."),
                    ],
                ],
            ],
            "confidence": ["type": "number", "description": "0 to 1."],
            "feedback": string("1-2 warm, playful sentences for the player."),
        ],
    ]

    private static let stringList: JSONValue = ["type": "array", "items": ["type": "string"]]

    static let venue: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["venue_name", "summary", "areas", "typical_things", "events_and_highlights", "sponsors", "rules_and_etiquette"],
        "properties": [
            "venue_name": string("Venue or event name."),
            "summary": string("2-3 sentence summary."),
            "areas": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "description"],
                    "properties": ["name": string("Area name."), "description": string("One sentence.")],
                ],
            ],
            "typical_things": stringList,
            "events_and_highlights": stringList,
            "sponsors": stringList,
            "rules_and_etiquette": stringList,
        ],
    ]

    /// Gemini's JSON-schema subset only documents `enum` on strings, so drop it elsewhere
    /// (the validators enforce those values anyway).
    static func geminiCompatible(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(var object):
            if object["enum"] != nil, object["type"] != .string("string") { object.removeValue(forKey: "enum") }
            return .object(object.mapValues(geminiCompatible))
        case .array(let items):
            return .array(items.map(geminiCompatible))
        default:
            return schema
        }
    }
}
