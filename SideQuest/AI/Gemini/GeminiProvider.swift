import Foundation

/// Gemini (and Gemma) via the Gemini Developer API with the player's own key.
/// Gemini models use JSON-schema output and Google Search; Gemma models get the schema in the
/// prompt instead, and every response goes through the same validators as Claude's.
struct GeminiProvider: AIProvider {
    let client: GeminiClient
    var model: AIConfig.GeminiModel = AIConfig.geminiDefaultModel
    var strongModel: AIConfig.GeminiModel = AIConfig.geminiStrongModel
    var researchModel: AIConfig.GeminiModel = AIConfig.geminiResearchModel
    var usage: AIUsageSink = { _ in }

    var kind: ProviderKind { .gemini }
    var supportsStrongerRecheck: Bool { strongModel != model }

    // MARK: Research

    func research(venue: String) async throws -> VenueContext {
        var notes: String
        var sources: [String] = []
        var usedSearch = researchModel.supportsSearch
        do {
            (notes, sources) = try await researchNotes(venue: venue, withSearch: researchModel.supportsSearch)
        } catch let error as AIError where [.webSearchUnavailable, .permissionDenied].contains(error) || error.isBadRequest {
            // Search isn't available on every key (e.g. the free tier): use the model's own knowledge.
            usedSearch = false
            (notes, sources) = try await researchNotes(venue: venue, withSearch: false)
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes = "No research notes available." }

        var venueContext = try await generateJSON(
            model: researchModel, kind: .research, system: QuestPrompts.venueStructuringSystem,
            parts: [GeminiRequest.text(QuestPrompts.venueStructuringUser(venue: venue, notes: notes))],
            schema: QuestSchemas.venue, maxTokens: AIConfig.researchMaxTokens) { try VenueJSON.decode(text: $0) }
        venueContext.sources = Array(sources.prefix(8))
        venueContext.usedWebSearch = usedSearch
        return venueContext
    }

    private func researchNotes(venue: String, withSearch: Bool) async throws -> (String, [String]) {
        let request = GeminiRequest(
            systemInstruction: .init(parts: [GeminiRequest.text(QuestPrompts.researchSystem)]),
            contents: [.init(role: "user", parts: [GeminiRequest.text(QuestPrompts.researchUser(venue: venue))])],
            tools: withSearch ? [["googleSearch": [:]]] : nil,
            generationConfig: generationConfig(model: researchModel, maxTokens: AIConfig.researchMaxTokens, schema: nil))
        let response = try await send(request, model: researchModel, kind: .research, timeout: AIConfig.researchTimeout)
        try checkFinish(response)
        var seen = Set<String>()
        return (response.text, response.sourceURLs.filter { seen.insert($0).inserted })
    }

    // MARK: Generation

    func generateQuest(context: QuestContext) async throws -> Quest {
        try await generateJSON(
            model: model, kind: .generate, system: QuestPrompts.system(for: context),
            parts: [GeminiRequest.text(QuestPrompts.generationUser(context))],
            schema: QuestSchemas.quest, maxTokens: AIConfig.generationMaxTokens) { try QuestJSON.decode(text: $0) }
    }

    // MARK: Verification

    func verify(photos: [Data], criteria: [String], quest: Quest, useStrongerModel: Bool) async throws -> Verdict {
        let chosen = useStrongerModel ? strongModel : model
        let imageParts: [JSONValue] = photos.count > 1
            ? photos.enumerated().flatMap { [GeminiRequest.text("Photo \($0.offset + 1) of \(photos.count):"), GeminiRequest.jpeg($0.element)] }
            : photos.map(GeminiRequest.jpeg)
        let parts = imageParts + [GeminiRequest.text(QuestPrompts.verificationUser(quest: quest, criteria: criteria, photoCount: photos.count))]
        let attempt = {
            try await generateJSON(model: chosen, kind: useStrongerModel ? .recheck : .verify,
                                   system: QuestPrompts.verificationSystem, parts: parts, schema: QuestSchemas.verdict,
                                   maxTokens: AIConfig.verificationMaxTokens, thinking: useStrongerModel ? "medium" : nil) {
                try VerdictJSON.decode(text: $0)
            }
        }
        var verdict: Verdict
        do {
            verdict = try await attempt()
        } catch is AIJSONError where !chosen.supportsJSONSchema {
            // Gemma writes JSON from instructions alone; give it one more go.
            verdict = try await attempt()
        }
        verdict.recheckedWithStrongerModel = useStrongerModel ? true : nil
        return verdict
    }

    // MARK: Helpers

    private func generateJSON<T>(model: AIConfig.GeminiModel, kind: AICallKind, system: String, parts: [JSONValue],
                                 schema: JSONValue, maxTokens: Int, thinking: String? = nil,
                                 parse: (String) throws -> T) async throws -> T {
        var systemText = system
        if !model.supportsJSONSchema {
            systemText += "\n\nReply with only one JSON object (no code fences, no other text) that matches this JSON schema:\n"
                + Self.compactJSON(QuestSchemas.geminiCompatible(schema))
        }
        let request = GeminiRequest(
            systemInstruction: .init(parts: [GeminiRequest.text(systemText)]),
            contents: [.init(role: "user", parts: parts)],
            generationConfig: generationConfig(model: model, maxTokens: maxTokens,
                                               schema: model.supportsJSONSchema ? Optional(schema) : Optional.none, thinking: thinking))
        let response = try await send(request, model: model, kind: kind)
        try checkFinish(response)
        return try parse(response.text)
    }

    func generationConfig(model: AIConfig.GeminiModel, maxTokens: Int, schema: JSONValue?, thinking: String? = nil) -> JSONValue {
        var config: [String: JSONValue] = [
            "maxOutputTokens": .int(maxTokens),
            "thinkingConfig": ["thinkingLevel": .string(thinking ?? model.fastThinkingLevel)],
        ]
        // (JSONValue is nil-literal-convertible, so also guard against an accidental `.null`.)
        if let schema, schema != .null {
            config["responseMimeType"] = "application/json"
            config["responseJsonSchema"] = QuestSchemas.geminiCompatible(schema)
        }
        return .object(config)
    }

    private func checkFinish(_ response: GeminiResponse) throws {
        if response.promptFeedback?.blockReason != nil { throw AIError.refused }
        guard response.candidates?.isEmpty == false else { throw AIError.invalidResponse("No candidates") }
        if let reason = response.finishReason {
            if reason == "MAX_TOKENS" { throw AIError.truncated }
            if GeminiResponse.blockedFinishReasons.contains(reason) { throw AIError.refused }
        }
    }

    private func send(_ request: GeminiRequest, model: AIConfig.GeminiModel, kind: AICallKind,
                      timeout: TimeInterval = AIConfig.requestTimeout) async throws -> GeminiResponse {
        let response = try await client.generateContent(model: model.rawValue, request, timeout: timeout)
        let cost = AIConfig.estimatedGeminiCostUSD(model: model, promptTokens: response.inputTokens,
                                                   outputTokens: response.outputTokens, searches: response.searchQueryCount)
        await usage(AICallRecord(kind: kind, model: model.rawValue, inputTokens: response.inputTokens,
                                 outputTokens: response.outputTokens, webSearches: response.searchQueryCount, costUSD: cost))
        return response
    }

    static func compactJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

extension AIError {
    var isBadRequest: Bool {
        if case .badRequest = self { return true }
        return false
    }
}
