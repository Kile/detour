import Foundation

enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case gemini
    case demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Google)"
        case .demo: return "Demo mode (offline)"
        }
    }
}

enum AICallKind: String, Codable, Sendable {
    case research, generate, verify, recheck
}

/// One AI call, for the debug counter and cost estimate.
struct AICallRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    var kind: AICallKind
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var webSearches: Int
    var costUSD: Double
}

typealias AIUsageSink = @Sendable (AICallRecord) async -> Void

/// Everything the app needs from an AI backend. App logic only talks to this protocol, so
/// providers (Claude, the mock, a future Gemini fallback) are interchangeable. Providers decode
/// every response through the shared JSON validators (`QuestJSON`, `VerdictJSON`, `VenueJSON`);
/// `QuestEngine` then applies the place, money and safety rules.
protocol AIProvider: Sendable {
    var kind: ProviderKind { get }
    /// Whether `verify(…, useStrongerModel: true)` uses a different, stronger model.
    var supportsStrongerRecheck: Bool { get }

    /// Researches a venue from a one-line description (web search where available).
    func research(venue: String) async throws -> VenueContext
    /// Writes one quest for the given context.
    func generateQuest(context: QuestContext) async throws -> Quest
    /// Checks prepared JPEGs (resized, faces blurred, metadata stripped) against the quest's
    /// success criteria. Several photos are judged together (one per find).
    func verify(photos: [Data], criteria: [String], quest: Quest, useStrongerModel: Bool) async throws -> Verdict
}

/// User-facing errors. Messages are written for players, not developers.
enum AIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case outOfCredit
    case rateLimited
    case overloaded
    case offline
    case timeout
    case permissionDenied
    case modelUnavailable(String)
    case webSearchUnavailable
    case refused
    case truncated
    case badRequest(String)
    case invalidResponse(String)
    case server(Int)
    /// Gemini free tier hit its rate limit.
    case coolingDown(seconds: Int?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your API key in Settings, or switch to demo mode."
        case .invalidAPIKey:
            return "That API key didn't work. Check it in Settings → API keys."
        case .outOfCredit:
            return "Your AI account is out of credit or needs billing set up. Top up with your provider, or switch to demo mode for now."
        case .rateLimited:
            return "The AI is getting a lot of quest requests right now. Give it a few seconds and try again."
        case .overloaded:
            return "The AI is busy at the moment. Try again in a minute."
        case .offline:
            return "You seem to be offline. Check your connection and try again."
        case .timeout:
            return "That took too long. Check your connection and try again."
        case .permissionDenied:
            return "This API key isn't allowed to do that. Check its permissions with your AI provider."
        case .modelUnavailable(let model):
            return "The model \(model) isn't available to your account. Pick another model in Settings."
        case .webSearchUnavailable:
            return "Web search isn't enabled for this API key."
        case .refused:
            return "The AI passed on that one. Let's try a different quest."
        case .truncated:
            return "The AI's answer got cut off. Try again."
        case .badRequest:
            return "Something went wrong talking to the AI. Try again."
        case .invalidResponse:
            return "The AI sent back something unexpected. Try again."
        case .server:
            return "The AI had a hiccup. Try again in a moment."
        case .coolingDown(let seconds):
            if let seconds, seconds > 0 {
                return "Gemini is cooling down (free-tier limit). Try again in about \(seconds) seconds."
            }
            return "Gemini is cooling down (free-tier limit). Give it a minute and try again."
        }
    }

    /// Developer detail for the debug screen. Never contains the API key.
    var debugDetail: String {
        switch self {
        case .badRequest(let m), .invalidResponse(let m): return m
        case .server(let code): return "HTTP \(code)"
        default: return String(describing: self)
        }
    }
}
