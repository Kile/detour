import Foundation
import CoreGraphics

/// Single source of truth for AI model IDs, API versions and pricing.
/// Checked against the Anthropic docs (platform.claude.com/docs) in November 2026.
enum AIConfig {
    // MARK: Anthropic Messages API

    static let anthropicBaseURL = URL(string: "https://api.anthropic.com")!
    /// `anthropic-version` header. 2026-10-21 rejects `temperature`/`top_p`/`top_k`, so we never send them.
    static let anthropicVersion = "2026-10-21"
    /// Where users create an API key.
    static let apiKeyConsoleURL = URL(string: "https://platform.claude.com/settings/keys")!

    enum Model: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Fast, cheap, vision-capable. Default for generation, verification and venue research.
        case haiku = "claude-haiku-5-5"
        /// Stronger model, used for the optional "re-check" of unsure verdicts.
        case sonnet = "claude-sonnet-5-5"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .haiku: return "Claude Haiku 5.5 (fast)"
            case .sonnet: return "Claude Sonnet 5.5 (stronger)"
            }
        }

        /// USD per million tokens. Haiku 5.5 has a cheaper rate card for prompts up to 100K tokens.
        func pricing(promptTokens: Int) -> (input: Double, output: Double) {
            switch self {
            case .haiku: return promptTokens <= 100_000 ? (0.10, 0.50) : (0.50, 2.50)
            case .sonnet: return (2.00, 10.00)
            }
        }

        /// Cache reads are billed at a fraction of the input price.
        var cacheReadMultiplier: Double {
            switch self {
            case .haiku: return 0.10
            case .sonnet: return 0.05
            }
        }
    }

    static let generationModel: Model = .haiku
    static let verificationModel: Model = .haiku
    static let strongVerificationModel: Model = .sonnet
    static let researchModel: Model = .haiku

    /// Effort levels (`output_config.effort`). Lower = faster and cheaper.
    static let generationEffort = "low"
    static let verificationEffort = "low"
    static let strongVerificationEffort = "medium"
    static let researchEffort = "low"

    static let generationMaxTokens = 4_000
    static let verificationMaxTokens = 3_000
    static let researchMaxTokens = 8_000

    // MARK: Web search (server-side tool, venue research only)

    /// Basic web search: supported on Claude Haiku 5.5 and calls search directly.
    static let webSearchToolType = "web_search_20250305"
    static let webSearchMaxUses = 5
    /// $10 per 1,000 searches.
    static let webSearchCostUSD = 0.01
    /// How many times we resume a research turn that returned `pause_turn`.
    static let maxPauseTurnContinuations = 2

    // MARK: Networking

    static let requestTimeout: TimeInterval = 60
    static let researchTimeout: TimeInterval = 150
    /// Longest wait we honour from a `retry-after` header before the single 429 retry.
    static let maxRetryAfterSeconds: Double = 8
    static let defaultRetryBackoffSeconds: Double = 2

    // MARK: Images

    static let maxImageLongEdge: CGFloat = 1_500
    static let jpegQuality: CGFloat = 0.8
    static let thumbnailLongEdge: CGFloat = 360

    // MARK: Gemini Developer API (checked against ai.google.dev, November 2026)

    static let geminiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/")!
    /// Where users create a Gemini API key (Google AI Studio).
    static let geminiKeyConsoleURL = URL(string: "https://aistudio.google.com/apikey")!

    enum GeminiModel: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Fastest, cheapest Gemini with image input. Free tier available.
        case flashLite = "gemini-3.5-flash-lite"
        /// Stronger Flash model; used for the optional re-check.
        case flash = "gemini-3.8-flash"
        /// Open Gemma 4 models served by the Gemini API (free tier only). Lenient with photos.
        case gemma31b = "gemma-4-31b-it"
        case gemma26b = "gemma-4-26b-a4b-it"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .flashLite: return "Gemini 3.5 Flash-Lite (fast)"
            case .flash: return "Gemini 3.8 Flash (stronger)"
            case .gemma31b: return "Gemma 4 31B (free tier)"
            case .gemma26b: return "Gemma 4 26B (free tier, faster)"
            }
        }

        var isGemma: Bool { self == .gemma31b || self == .gemma26b }
        /// Gemma's JSON-schema output isn't documented, so we ask for JSON in the prompt instead.
        var supportsJSONSchema: Bool { !isGemma }
        /// Google Search grounding isn't available for Gemma.
        var supportsSearch: Bool { !isGemma }

        /// Lowest-latency thinking level each model accepts.
        var fastThinkingLevel: String {
            switch self {
            case .flash: return "low"          // 3.8 Flash has no "minimal"
            default: return "minimal"
            }
        }

        /// Paid-tier USD per million tokens. Free-tier keys pay nothing; Gemma is free-tier only.
        var pricing: (input: Double, output: Double) {
            switch self {
            case .flashLite: return (0.30, 2.50)
            case .flash: return (0.75, 3.75)   // through 31 Dec 2026, then $1.50 / $7.50
            case .gemma31b, .gemma26b: return (0, 0)
            }
        }
    }

    static let geminiDefaultModel: GeminiModel = .flashLite
    static let geminiStrongModel: GeminiModel = .flash
    /// Venue research needs Google Search, which Gemma doesn't have.
    static let geminiResearchModel: GeminiModel = .flashLite
    /// $14 per 1,000 search queries after the monthly free allowance (paid tier only).
    static let geminiSearchCostUSD = 0.014

    static func estimatedGeminiCostUSD(model: GeminiModel, promptTokens: Int, outputTokens: Int, searches: Int = 0) -> Double {
        let price = model.pricing
        return (Double(promptTokens) * price.input + Double(outputTokens) * price.output) / 1_000_000
            + Double(searches) * geminiSearchCostUSD
    }

    // MARK: Cost estimate

    static func estimatedCostUSD(model: Model, inputTokens: Int, outputTokens: Int,
                                 cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0,
                                 webSearches: Int = 0) -> Double {
        let promptTokens = inputTokens + cacheReadTokens + cacheWriteTokens
        let price = model.pricing(promptTokens: promptTokens)
        let input = Double(inputTokens) * price.input
            + Double(cacheReadTokens) * price.input * model.cacheReadMultiplier
            + Double(cacheWriteTokens) * price.input * 1.25
        let output = Double(outputTokens) * price.output
        return (input + output) / 1_000_000 + Double(webSearches) * webSearchCostUSD
    }
}
