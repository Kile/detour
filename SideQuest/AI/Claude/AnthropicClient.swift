import Foundation

/// Request body for `POST /v1/messages`. Only the fields this app needs.
/// No `temperature`/`top_p`/`top_k`: API version 2026-10-21 rejects them.
struct MessagesRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        var role: String
        var content: [JSONValue]
    }

    struct OutputConfig: Encodable, Sendable {
        struct Format: Encodable, Sendable {
            var type = "json_schema"
            var schema: JSONValue
        }
        var effort: String?
        var format: Format?
    }

    var model: String
    var maxTokens: Int
    var system: String?
    var messages: [Message]
    var tools: [JSONValue]?
    var outputConfig: OutputConfig?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }

    static func text(_ text: String) -> JSONValue { ["type": "text", "text": .string(text)] }

    static func jpeg(_ data: Data) -> JSONValue {
        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(data.base64EncodedString())]]
    }
}

struct MessagesResponse: Decodable, Sendable {
    struct Usage: Decodable, Sendable {
        struct ServerToolUse: Decodable, Sendable {
            var webSearchRequests: Int?
            enum CodingKeys: String, CodingKey { case webSearchRequests = "web_search_requests" }
        }
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?
        var serverToolUse: ServerToolUse?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case serverToolUse = "server_tool_use"
        }
    }

    var id: String
    var model: String
    var content: [JSONValue]
    var stopReason: String?
    var usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
    }

    /// Text blocks only. Responses can start with `thinking` blocks, so never read by position.
    var text: String {
        content.filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
    }

    /// Source URLs Claude cited (web search), de-duplicated in order.
    var citedURLs: [String] {
        var seen = Set<String>()
        var urls: [String] = []
        for block in content where block["type"]?.stringValue == "text" {
            for citation in block["citations"]?.arrayValue ?? [] {
                if let url = citation["url"]?.stringValue, seen.insert(url).inserted { urls.append(url) }
            }
        }
        return urls
    }

    /// URLs of every search result, as a fallback when nothing was cited.
    var searchResultURLs: [String] {
        content.filter { $0["type"]?.stringValue == "web_search_tool_result" }
            .flatMap { $0["content"]?.arrayValue ?? [] }
            .compactMap { $0["url"]?.stringValue }
    }

    var webSearchCount: Int { usage.serverToolUse?.webSearchRequests ?? 0 }
}

/// A small typed client for the Anthropic Messages API over URLSession.
/// The API key is read from the Keychain on each call and is never logged.
final class AnthropicClient: @unchecked Sendable {
    typealias Sleeper = @Sendable (Double) async throws -> Void

    private let apiKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL: URL
    private let sleep: Sleeper

    init(apiKey: @escaping @Sendable () -> String?,
         session: URLSession = .shared,
         baseURL: URL = AIConfig.anthropicBaseURL,
         sleep: @escaping Sleeper = { seconds in try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
        self.sleep = sleep
    }

    func createMessage(_ body: MessagesRequest, timeout: TimeInterval = AIConfig.requestTimeout) async throws -> MessagesResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(body)
        let responseData = try await send(path: "v1/messages", method: "POST", body: data, timeout: timeout)
        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: responseData)
        } catch {
            throw AIError.invalidResponse("Couldn't decode Messages response")
        }
    }

    /// Checks a key without spending tokens (the Models endpoint is free).
    func validateKey() async throws {
        _ = try await send(path: "v1/models?limit=1", method: "GET", body: nil, timeout: 20)
    }

    // MARK: Transport

    private func send(path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AIError.missingAPIKey
        }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw AIError.badRequest("Bad URL") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(AIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        // One retry with backoff for rate limits and transient server errors.
        var attempt = 0
        while true {
            let (data, response) = try await perform(request)
            let status = response.statusCode
            if (200..<300).contains(status) { return data }

            let error = Self.map(status: status, body: data)
            let retryable = [429, 500, 502, 503, 504, 529].contains(status)
            if retryable && attempt == 0 {
                attempt += 1
                try await sleep(Self.backoff(for: response))
                continue
            }
            throw error
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("Not an HTTP response") }
            return (data, http)
        } catch let error as URLError {
            throw Self.map(urlError: error)
        }
    }

    static func backoff(for response: HTTPURLResponse) -> Double {
        if let header = response.value(forHTTPHeaderField: "retry-after"), let seconds = Double(header) {
            return min(max(seconds, 0.5), AIConfig.maxRetryAfterSeconds)
        }
        return AIConfig.defaultRetryBackoffSeconds
    }

    static func map(urlError: URLError) -> Error {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .internationalRoamingOff, .dnsLookupFailed:
            return AIError.offline
        case .timedOut:
            return AIError.timeout
        case .cancelled:
            return CancellationError()
        default:
            return AIError.offline
        }
    }

    static func map(status: Int, body: Data) -> AIError {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { var type: String?; var message: String? }
            var error: Inner?
        }
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        let type = envelope?.error?.type ?? ""
        let message = envelope?.error?.message ?? ""
        let lower = message.lowercased()

        switch status {
        case 400:
            if lower.contains("credit balance") || type == "billing_error" { return .outOfCredit }
            if lower.contains("web search") && (lower.contains("not enabled") || lower.contains("disabled")) {
                return .webSearchUnavailable
            }
            return .badRequest(message.isEmpty ? "HTTP 400" : message)
        case 401: return .invalidAPIKey
        case 402: return .outOfCredit
        case 403: return .permissionDenied
        case 404: return .modelUnavailable(message.isEmpty ? "requested model" : message)
        case 413: return .badRequest("Request too large")
        case 429: return .rateLimited
        case 500, 502, 503, 504, 529: return .overloaded
        default: return .server(status)
        }
    }
}
