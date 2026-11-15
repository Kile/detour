import Foundation

/// Request body for `models/{model}:generateContent` (Gemini Developer API, v1beta).
/// No temperature/topP/topK: current Gemini models ignore them and will reject them.
struct GeminiRequest: Encodable, Sendable {
    struct Content: Encodable, Sendable {
        var role: String?
        var parts: [JSONValue]
    }

    var systemInstruction: Content?
    var contents: [Content]
    var tools: [JSONValue]?
    var generationConfig: JSONValue?

    static func text(_ text: String) -> JSONValue { ["text": .string(text)] }

    static func jpeg(_ data: Data) -> JSONValue {
        ["inlineData": ["mimeType": "image/jpeg", "data": .string(data.base64EncodedString())]]
    }
}

struct GeminiResponse: Decodable, Sendable {
    struct Part: Decodable, Sendable {
        var text: String?
        /// True for the model's own reasoning, which we never show or parse.
        var thought: Bool?
    }

    struct Content: Decodable, Sendable { var parts: [Part]? }

    struct GroundingMetadata: Decodable, Sendable {
        struct Chunk: Decodable, Sendable {
            struct Web: Decodable, Sendable { var uri: String?; var title: String? }
            var web: Web?
        }
        var webSearchQueries: [String]?
        var groundingChunks: [Chunk]?
    }

    struct Candidate: Decodable, Sendable {
        var content: Content?
        var finishReason: String?
        var groundingMetadata: GroundingMetadata?
    }

    struct PromptFeedback: Decodable, Sendable { var blockReason: String? }

    struct Usage: Decodable, Sendable {
        var promptTokenCount: Int?
        var candidatesTokenCount: Int?
        var thoughtsTokenCount: Int?
        var toolUsePromptTokenCount: Int?
    }

    var candidates: [Candidate]?
    var promptFeedback: PromptFeedback?
    var usageMetadata: Usage?

    /// Answer text from the first candidate, skipping thought parts.
    var text: String {
        (candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
    }

    var finishReason: String? { candidates?.first?.finishReason }
    var searchQueryCount: Int { candidates?.first?.groundingMetadata?.webSearchQueries?.count ?? 0 }
    var sourceURLs: [String] {
        (candidates?.first?.groundingMetadata?.groundingChunks ?? []).compactMap { $0.web?.uri }
    }

    var inputTokens: Int { (usageMetadata?.promptTokenCount ?? 0) + (usageMetadata?.toolUsePromptTokenCount ?? 0) }
    /// Thinking tokens are billed as output.
    var outputTokens: Int { (usageMetadata?.candidatesTokenCount ?? 0) + (usageMetadata?.thoughtsTokenCount ?? 0) }

    static let blockedFinishReasons: Set<String> = [
        "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT",
    ]
}

/// A small typed client for the Gemini Developer API over URLSession, using the player's own
/// key from Google AI Studio (stored in the Keychain, sent only in a header, never logged).
final class GeminiClient: @unchecked Sendable {
    typealias Sleeper = @Sendable (Double) async throws -> Void

    private let apiKey: @Sendable () -> String?
    private let session: URLSession
    private let baseURL: URL
    private let sleep: Sleeper

    init(apiKey: @escaping @Sendable () -> String?,
         session: URLSession = .shared,
         baseURL: URL = AIConfig.geminiBaseURL,
         sleep: @escaping Sleeper = { seconds in try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
        self.sleep = sleep
    }

    func generateContent(model: String, _ body: GeminiRequest, timeout: TimeInterval = AIConfig.requestTimeout) async throws -> GeminiResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(body)
        let responseData = try await send(path: "models/\(model):generateContent", method: "POST", body: data,
                                          timeout: timeout, model: model)
        do {
            return try JSONDecoder().decode(GeminiResponse.self, from: responseData)
        } catch {
            throw AIError.invalidResponse("Couldn't decode Gemini response")
        }
    }

    /// Checks the key exists (the models list is free; it doesn't prove billing/tier).
    func validateKey() async throws {
        _ = try await send(path: "models?pageSize=1", method: "GET", body: nil, timeout: 20, model: nil)
    }

    // MARK: Transport

    private func send(path: String, method: String, body: Data?, timeout: TimeInterval, model: String?) async throws -> Data {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AIError.missingAPIKey
        }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw AIError.badRequest("Bad URL") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        // Header rather than a ?key= query parameter, so the key never appears in URLs or logs.
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        var attempt = 0
        while true {
            let (data, response) = try await perform(request)
            let status = response.statusCode
            if (200..<300).contains(status) { return data }

            let parsed = Self.parseError(data)
            let retryable = [429, 500, 502, 503, 504].contains(status)
            if retryable && attempt == 0 {
                attempt += 1
                try await sleep(min(parsed.retryDelay ?? AIConfig.defaultRetryBackoffSeconds, AIConfig.maxRetryAfterSeconds))
                continue
            }
            throw Self.map(status: status, error: parsed, model: model)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse("Not an HTTP response") }
            return (data, http)
        } catch let error as URLError {
            throw AnthropicClient.map(urlError: error)
        }
    }

    struct ParsedError: Equatable {
        var status: String = ""
        var message: String = ""
        var reasons: [String] = []
        var retryDelay: Double?
    }

    /// Understands the google.rpc.Status envelope: {"error": {"code", "message", "status", "details": [...]}}.
    static func parseError(_ data: Data) -> ParsedError {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let error = json["error"] else {
            return ParsedError()
        }
        var parsed = ParsedError(status: error["status"]?.stringValue ?? "", message: error["message"]?.stringValue ?? "")
        for detail in error["details"]?.arrayValue ?? [] {
            if let reason = detail["reason"]?.stringValue { parsed.reasons.append(reason) }
            if let delay = detail["retryDelay"]?.stringValue, let seconds = Double(delay.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) {
                parsed.retryDelay = seconds
            }
        }
        return parsed
    }

    static func map(status: Int, error: ParsedError, model: String?) -> AIError {
        let message = error.message.lowercased()
        let invalidKey = error.reasons.contains("API_KEY_INVALID") || message.contains("api key not valid")
            || message.contains("api key expired") || message.contains("api_key_invalid")
        let mentionsSearch = message.contains("google_search") || message.contains("googlesearch")
            || message.contains("search") && (message.contains("ground") || message.contains("not supported") || message.contains("not available"))

        switch status {
        case 400:
            if invalidKey { return .invalidAPIKey }
            if mentionsSearch { return .webSearchUnavailable }
            if message.contains("billing") || message.contains("prepay") { return .outOfCredit }
            return .badRequest(error.message.isEmpty ? "HTTP 400" : error.message)
        case 401: return .invalidAPIKey
        case 402: return .outOfCredit
        case 403:
            if invalidKey || message.contains("leaked") { return .invalidAPIKey }
            if mentionsSearch { return .webSearchUnavailable }
            if message.contains("billing") || message.contains("payment") { return .outOfCredit }
            return .permissionDenied
        case 404: return .modelUnavailable(model ?? "requested model")
        case 429: return .coolingDown(seconds: error.retryDelay.map { Int($0.rounded(.up)) })
        case 500, 502, 503, 504: return .overloaded
        default: return .server(status)
        }
    }
}
