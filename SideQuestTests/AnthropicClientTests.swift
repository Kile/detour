import XCTest
@testable import SideQuest

/// Intercepts URLSession requests and replies from a queue of canned responses.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
        var error: URLError? = nil
    }

    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data)] = []

    static func reset() {
        replies = []
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.requests.append((request, body))
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let reply = Self.replies.removeFirst()
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AnthropicClientTests: XCTestCase {
    var session: URLSession!
    var sleeps: [Double] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        sleeps = []
    }

    func makeClient(key: String? = "sk-ant-test-key-1234567890") -> AnthropicClient {
        AnthropicClient(apiKey: { key }, session: session, sleep: { [weak self] seconds in self?.sleeps.append(seconds) })
    }

    static func messageResponse(text: String, stopReason: String = "end_turn", extraBlocks: [String] = []) -> Data {
        let textBlock = try! JSONSerialization.data(withJSONObject: ["type": "text", "text": text])
        let blocks = [#"{"type":"thinking","thinking":"","signature":"sig"}"#] + extraBlocks + [String(data: textBlock, encoding: .utf8)!]
        return Data("""
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5","content":[\(blocks.joined(separator: ","))],
         "stop_reason":"\(stopReason)","usage":{"input_tokens":1200,"output_tokens":300,"server_tool_use":{"web_search_requests":2}}}
        """.utf8)
    }

    static func errorBody(_ type: String, _ message: String) -> Data {
        Data(#"{"type":"error","error":{"type":"\#(type)","message":"\#(message)"}}"#.utf8)
    }

    func simpleRequest() -> MessagesRequest {
        MessagesRequest(model: "claude-haiku-5-5", maxTokens: 100, system: "sys",
                        messages: [.init(role: "user", content: [MessagesRequest.text("hi")])],
                        outputConfig: .init(effort: "low", format: .init(schema: QuestSchemas.quest)))
    }

    // MARK: Request shape

    func testHeadersAndBody() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: "{}"))]
        _ = try await makeClient().createMessage(simpleRequest())

        let (request, body) = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-key-1234567890")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), AIConfig.anthropicVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 100)
        XCTAssertNil(json["temperature"], "2026-10-21 rejects temperature")
        XCTAssertNil(json["top_p"])
        XCTAssertNil(json["tools"], "nil optionals are omitted")
        let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "low")
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testImageBlockIsBase64JPEG() throws {
        let block = MessagesRequest.jpeg(Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(block["type"]?.stringValue, "image")
        XCTAssertEqual(block["source"]?["type"]?.stringValue, "base64")
        XCTAssertEqual(block["source"]?["media_type"]?.stringValue, "image/jpeg")
        XCTAssertEqual(block["source"]?["data"]?.stringValue, "/9j/")
    }

    func testResponseTextSkipsThinkingBlocks() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: #"{"ok":true}"#))]
        let response = try await makeClient().createMessage(simpleRequest())
        XCTAssertEqual(response.text, #"{"ok":true}"#)
        XCTAssertEqual(response.usage.inputTokens, 1200)
        XCTAssertEqual(response.webSearchCount, 2)
    }

    // MARK: Errors

    func testMissingKey() async {
        await assertThrows(.missingAPIKey) { try await self.makeClient(key: nil).createMessage(self.simpleRequest()) }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "No request without a key")
    }

    func testInvalidKey() async {
        StubURLProtocol.replies = [.init(status: 401, body: Self.errorBody("authentication_error", "invalid x-api-key"))]
        await assertThrows(.invalidAPIKey) { try await self.makeClient().createMessage(self.simpleRequest()) }
    }

    func testOutOfCredit() async {
        StubURLProtocol.replies = [.init(status: 400, body: Self.errorBody("invalid_request_error",
            "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."))]
        await assertThrows(.outOfCredit) { try await self.makeClient().createMessage(self.simpleRequest()) }
        StubURLProtocol.replies = [.init(status: 402, body: Self.errorBody("billing_error", "Billing problem"))]
        await assertThrows(.outOfCredit) { try await self.makeClient().createMessage(self.simpleRequest()) }
    }

    func testRateLimitRetriesOnceWithBackoffThenSucceeds() async throws {
        StubURLProtocol.replies = [
            .init(status: 429, body: Self.errorBody("rate_limit_error", "slow down"), headers: ["retry-after": "3"]),
            .init(status: 200, body: Self.messageResponse(text: "{}")),
        ]
        _ = try await makeClient().createMessage(simpleRequest())
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(sleeps, [3])
    }

    func testRateLimitTwiceGivesUp() async {
        StubURLProtocol.replies = [
            .init(status: 429, body: Self.errorBody("rate_limit_error", "slow down")),
            .init(status: 429, body: Self.errorBody("rate_limit_error", "slow down")),
            .init(status: 200, body: Self.messageResponse(text: "{}")),
        ]
        await assertThrows(.rateLimited) { try await self.makeClient().createMessage(self.simpleRequest()) }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(sleeps, [AIConfig.defaultRetryBackoffSeconds])
    }

    func testRetryAfterIsCapped() async throws {
        StubURLProtocol.replies = [
            .init(status: 529, body: Self.errorBody("overloaded_error", "busy"), headers: ["retry-after": "120"]),
            .init(status: 200, body: Self.messageResponse(text: "{}")),
        ]
        _ = try await makeClient().createMessage(simpleRequest())
        XCTAssertEqual(sleeps, [AIConfig.maxRetryAfterSeconds])
    }

    func testOffline() async {
        StubURLProtocol.replies = [.init(status: 0, body: Data(), error: URLError(.notConnectedToInternet))]
        await assertThrows(.offline) { try await self.makeClient().createMessage(self.simpleRequest()) }
    }

    func testValidateKeyUsesFreeModelsEndpoint() async throws {
        StubURLProtocol.replies = [.init(status: 200, body: Data(#"{"data":[]}"#.utf8))]
        try await makeClient().validateKey()
        let request = try XCTUnwrap(StubURLProtocol.requests.first?.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/models")
    }

    // MARK: ClaudeProvider end-to-end against the stub

    func testProviderGeneratesValidatedQuest() async throws {
        let questText = String(data: questJSON(), encoding: .utf8)!
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: questText))]
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [AICallRecord] = []
            func append(_ call: AICallRecord) { lock.withLock { storage.append(call) } }
            var calls: [AICallRecord] { lock.withLock { storage } }
        }
        let recorder = Recorder()
        let provider = ClaudeProvider(client: makeClient(), usage: { call in recorder.append(call) })
        let quest = try await provider.generateQuest(context: makeContext())
        XCTAssertEqual(quest.title, "Door Collector")
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.kind, .generate)
        XCTAssertGreaterThan(recorder.calls.first?.costUSD ?? 0, 0)

        let body = try XCTUnwrap(StubURLProtocol.requests.first?.body)
        let bodyText = String(data: body, encoding: .utf8)!
        XCTAssertTrue(bodyText.contains("The British Museum"), "Place names are sent")
        XCTAssertFalse(bodyText.contains("51.519"), "Coordinates are never sent")
        XCTAssertFalse(bodyText.contains("-0.126"), "Coordinates are never sent")
    }

    func testProviderSurfacesRefusalAndTruncation() async {
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: "", stopReason: "refusal"))]
        await assertThrows(.refused) { try await ClaudeProvider(client: self.makeClient()).generateQuest(context: makeContext()) }
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: "{\"title\":", stopReason: "max_tokens"))]
        await assertThrows(.truncated) { try await ClaudeProvider(client: self.makeClient()).generateQuest(context: makeContext()) }
    }

    func testProviderVerifiesWithImageAndStrongerModel() async throws {
        let verdictJSON = #"{"verdict":"pass","criteria":[{"criterion":"A vase","met":true,"reason":"Visible"}],"confidence":0.9,"feedback":"Nice!"}"#
        StubURLProtocol.replies = [.init(status: 200, body: Self.messageResponse(text: verdictJSON))]
        let verdict = try await ClaudeProvider(client: makeClient())
            .verify(photos: [Data([0xFF, 0xD8])], criteria: ["A vase"], quest: makeQuest(), useStrongerModel: true)
        XCTAssertEqual(verdict.verdict, .pass)
        XCTAssertEqual(verdict.recheckedWithStrongerModel, true)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, AIConfig.strongVerificationModel.rawValue)
        let content = try XCTUnwrap(((json["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "image", "Image goes before the text")
    }

    func testResearchUsesWebSearchResumesPausedTurnAndStructures() async throws {
        let citation = #"{"type":"text","text":"It has a Great Hall.","citations":[{"type":"web_search_result_location","url":"https://example.com/venue","title":"Venue","encrypted_index":"x","cited_text":"Great Hall"}]}"#
        let venueJSON = #"{"venue_name":"Test Venue","summary":"A venue.","areas":[{"name":"Great Hall","description":"Big."}],"typical_things":[],"events_and_highlights":[],"sponsors":[],"rules_and_etiquette":[]}"#
        StubURLProtocol.replies = [
            .init(status: 200, body: Self.messageResponse(text: "Searching…", stopReason: "pause_turn")),
            .init(status: 200, body: Self.messageResponse(text: "Done.", extraBlocks: [citation])),
            .init(status: 200, body: Self.messageResponse(text: venueJSON)),
        ]
        let venue = try await ClaudeProvider(client: makeClient()).research(venue: "Test Venue, London")
        XCTAssertEqual(venue.venueName, "Test Venue")
        XCTAssertEqual(venue.sources, ["https://example.com/venue"])
        XCTAssertEqual(venue.usedWebSearch, true)
        XCTAssertEqual(StubURLProtocol.requests.count, 3)

        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[0].body) as? [String: Any])
        let tool = try XCTUnwrap((first["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, AIConfig.webSearchToolType)
        XCTAssertEqual(tool["max_uses"] as? Int, AIConfig.webSearchMaxUses)

        // The resumed request echoes the paused assistant turn unchanged.
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[1].body) as? [String: Any])
        let messages = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant"])

        // The structuring call has no tools and asks for JSON.
        let third = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[2].body) as? [String: Any])
        XCTAssertNil(third["tools"])
        XCTAssertNotNil((third["output_config"] as? [String: Any])?["format"])
    }

    func testResearchFallsBackWhenWebSearchIsDisabled() async throws {
        let venueJSON = #"{"venue_name":"Test Venue","summary":"A venue.","areas":[],"typical_things":[],"events_and_highlights":[],"sponsors":[],"rules_and_etiquette":[]}"#
        StubURLProtocol.replies = [
            .init(status: 400, body: Self.errorBody("invalid_request_error", "Web search is not enabled for this organization")),
            .init(status: 200, body: Self.messageResponse(text: "Notes from memory.")),
            .init(status: 200, body: Self.messageResponse(text: venueJSON)),
        ]
        let venue = try await ClaudeProvider(client: makeClient()).research(venue: "Test Venue")
        XCTAssertEqual(venue.usedWebSearch, false)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.requests[1].body) as? [String: Any])
        XCTAssertNil(second["tools"])
    }

    func testCostEstimate() {
        // Haiku 5.5: $0.10 / $0.50 per MTok for prompts up to 100K tokens…
        XCTAssertEqual(AIConfig.estimatedCostUSD(model: .haiku, inputTokens: 100_000, outputTokens: 1_000_000), 0.51, accuracy: 0.0001)
        // …and $0.50 / $2.50 above that.
        XCTAssertEqual(AIConfig.estimatedCostUSD(model: .haiku, inputTokens: 200_000, outputTokens: 1_000_000), 2.60, accuracy: 0.0001)
        XCTAssertEqual(AIConfig.estimatedCostUSD(model: .sonnet, inputTokens: 0, outputTokens: 0, webSearches: 3), 0.03, accuracy: 0.0001)
    }

    // MARK: Helpers

    func assertThrows<T>(_ expected: AIError, file: StaticString = #filePath, line: UInt = #line,
                         _ body: @escaping () async throws -> T) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AIError, expected, file: file, line: line)
        }
    }
}

final class PromptTests: XCTestCase {
    func testPromptNeverContainsCoordinates() {
        let prompt = QuestPrompts.generationUser(makeContext())
        for place in samplePlaces {
            XCTAssertTrue(prompt.contains(place.name))
            XCTAssertFalse(prompt.contains(String(format: "%.3f", place.coordinate.latitude)))
        }
    }

    func testMoneyRulesInPrompt() {
        XCTAssertTrue(QuestPrompts.generationUser(makeContext(money: .init(enabled: false, maxSpendGBP: 20))).contains("MONEY: OFF"))
        let on = QuestPrompts.generationUser(makeContext(money: .init(enabled: true, maxSpendGBP: 7)))
        XCTAssertTrue(on.contains("£7"))
        XCTAssertTrue(on.contains("fully completable for free"))
    }

    func testNightAndFeedbackInPrompt() {
        var context = makeContext(now: nighttime)
        context.rejectionFeedback = ["mentions buying"]
        let prompt = QuestPrompts.generationUser(context)
        XCTAssertTrue(prompt.contains("dark"))
        XCTAssertTrue(prompt.contains("mentions buying"))
    }

    func testVenuePromptListsAreas() {
        let prompt = QuestPrompts.generationUser(makeContext(scope: .venue, venue: sampleVenue))
        XCTAssertTrue(prompt.contains("\"Great Hall\""))
        XCTAssertTrue(prompt.contains("do not rely on GPS"))
    }
}
