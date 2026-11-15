import Foundation

/// Claude via the Anthropic Messages API. Uses structured outputs (`output_config.format`) for
/// all JSON, which Claude Haiku 5.5 and Sonnet 5.5 support, and the server-side web search tool
/// for venue research.
struct ClaudeProvider: AIProvider {
    let client: AnthropicClient
    var generationModel: AIConfig.Model = AIConfig.generationModel
    var verificationModel: AIConfig.Model = AIConfig.verificationModel
    var strongModel: AIConfig.Model = AIConfig.strongVerificationModel
    var researchModel: AIConfig.Model = AIConfig.researchModel
    var usage: AIUsageSink = { _ in }

    var kind: ProviderKind { .claude }
    var supportsStrongerRecheck: Bool { strongModel != verificationModel }

    // MARK: Research

    func research(venue: String) async throws -> VenueContext {
        // 1) Web research → plain-text notes with citations.
        var notes: String
        var sources: [String] = []
        var usedWebSearch = true
        do {
            (notes, sources) = try await researchNotes(venue: venue, withWebSearch: true)
        } catch AIError.webSearchUnavailable {
            // Web search is disabled for this org: fall back to the model's own knowledge.
            usedWebSearch = false
            (notes, sources) = try await researchNotes(venue: venue, withWebSearch: false)
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = "No research notes available."
        }

        // 2) Notes → structured VenueContext. (Kept separate because citations from web search
        // can't be combined with structured output in one request.)
        let request = MessagesRequest(
            model: researchModel.rawValue,
            maxTokens: AIConfig.researchMaxTokens,
            system: QuestPrompts.venueStructuringSystem,
            messages: [.init(role: "user", content: [MessagesRequest.text(QuestPrompts.venueStructuringUser(venue: venue, notes: notes))])],
            outputConfig: .init(effort: AIConfig.researchEffort, format: .init(schema: QuestSchemas.venue)))
        let response = try await send(request, kind: .research, model: researchModel)
        var venueContext = try decode(response) { try VenueJSON.decode(text: $0) }
        venueContext.sources = Array(sources.prefix(8))
        venueContext.usedWebSearch = usedWebSearch
        return venueContext
    }

    private func researchNotes(venue: String, withWebSearch: Bool) async throws -> (String, [String]) {
        let tools: [JSONValue]? = withWebSearch
            ? [["type": .string(AIConfig.webSearchToolType), "name": "web_search", "max_uses": .int(AIConfig.webSearchMaxUses)]]
            : nil
        var messages: [MessagesRequest.Message] = [.init(role: "user", content: [MessagesRequest.text(QuestPrompts.researchUser(venue: venue))])]
        var collectedText: [String] = []
        var cited: [String] = []
        var resultURLs: [String] = []

        for continuation in 0...AIConfig.maxPauseTurnContinuations {
            let request = MessagesRequest(
                model: researchModel.rawValue,
                maxTokens: AIConfig.researchMaxTokens,
                system: QuestPrompts.researchSystem,
                messages: messages,
                tools: tools,
                outputConfig: .init(effort: AIConfig.researchEffort))
            let response = try await send(request, kind: .research, model: researchModel, timeout: AIConfig.researchTimeout)
            if response.stopReason == "refusal" { throw AIError.refused }
            collectedText.append(response.text)
            cited += response.citedURLs
            resultURLs += response.searchResultURLs

            // A long search turn can pause; send the assistant content back unchanged to resume.
            guard response.stopReason == "pause_turn", continuation < AIConfig.maxPauseTurnContinuations else { break }
            messages = [messages[0], .init(role: "assistant", content: response.content)]
        }

        var seen = Set<String>()
        let sources = (cited.isEmpty ? resultURLs : cited).filter { seen.insert($0).inserted }
        return (collectedText.joined(separator: "\n"), sources)
    }

    // MARK: Generation

    func generateQuest(context: QuestContext) async throws -> Quest {
        let system = QuestPrompts.system(for: context)
        let request = MessagesRequest(
            model: generationModel.rawValue,
            maxTokens: AIConfig.generationMaxTokens,
            system: system,
            messages: [.init(role: "user", content: [MessagesRequest.text(QuestPrompts.generationUser(context))])],
            // Hard quests get a little more thinking so they come out genuinely hard.
            outputConfig: .init(effort: context.difficulty == .hard ? "medium" : AIConfig.generationEffort,
                                format: .init(schema: QuestSchemas.quest)))
        let response = try await send(request, kind: .generate, model: generationModel)
        return try decode(response) { try QuestJSON.decode(text: $0) }
    }

    // MARK: Verification

    func verify(photos: [Data], criteria: [String], quest: Quest, useStrongerModel: Bool) async throws -> Verdict {
        let model = useStrongerModel ? strongModel : verificationModel
        let request = MessagesRequest(
            model: model.rawValue,
            maxTokens: AIConfig.verificationMaxTokens,
            system: QuestPrompts.verificationSystem,
            messages: [.init(role: "user", content: Self.photoBlocks(photos)
                + [MessagesRequest.text(QuestPrompts.verificationUser(quest: quest, criteria: criteria, photoCount: photos.count))])],
            outputConfig: .init(effort: useStrongerModel ? AIConfig.strongVerificationEffort : AIConfig.verificationEffort,
                                format: .init(schema: QuestSchemas.verdict)))
        let response = try await send(request, kind: useStrongerModel ? .recheck : .verify, model: model)
        var verdict = try decode(response) { try VerdictJSON.decode(text: $0) }
        verdict.recheckedWithStrongerModel = useStrongerModel ? true : nil
        return verdict
    }

    // MARK: Helpers

    /// Images first (as the docs recommend), each labelled when there are several.
    static func photoBlocks(_ photos: [Data]) -> [JSONValue] {
        guard photos.count > 1 else { return photos.map(MessagesRequest.jpeg) }
        return photos.enumerated().flatMap { index, data in
            [MessagesRequest.text("Photo \(index + 1) of \(photos.count):"), MessagesRequest.jpeg(data)]
        }
    }

    private func send(_ request: MessagesRequest, kind: AICallKind, model: AIConfig.Model,
                      timeout: TimeInterval = AIConfig.requestTimeout) async throws -> MessagesResponse {
        let response = try await client.createMessage(request, timeout: timeout)
        let u = response.usage
        let cost = AIConfig.estimatedCostUSD(model: model, inputTokens: u.inputTokens, outputTokens: u.outputTokens,
                                             cacheReadTokens: u.cacheReadInputTokens ?? 0,
                                             cacheWriteTokens: u.cacheCreationInputTokens ?? 0,
                                             webSearches: response.webSearchCount)
        await usage(AICallRecord(kind: kind, model: model.rawValue, inputTokens: u.inputTokens,
                                 outputTokens: u.outputTokens, webSearches: response.webSearchCount, costUSD: cost))
        return response
    }

    private func decode<T>(_ response: MessagesResponse, _ parse: (String) throws -> T) throws -> T {
        switch response.stopReason {
        case "refusal": throw AIError.refused
        case "max_tokens": throw AIError.truncated
        default: break
        }
        return try parse(response.text)
    }
}
