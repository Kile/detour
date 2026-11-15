import Foundation
import Observation

/// Preferences, persisted in UserDefaults. The API key is NOT here — it lives only in the Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Keys.onboarding) } }
    var providerKind: ProviderKind { didSet { defaults.set(providerKind.rawValue, forKey: Keys.provider) } }
    var scope: QuestScope { didSet { defaults.set(scope.rawValue, forKey: Keys.scope) } }
    var venueDescription: String { didSet { defaults.set(venueDescription, forKey: Keys.venue) } }
    var theme: QuestTheme? { didSet { defaults.set(theme?.rawValue, forKey: Keys.theme) } }
    var difficulty: DifficultyPreference { didSet { defaults.set(difficulty.rawValue, forKey: Keys.difficulty) } }
    var moneyEnabled: Bool { didSet { defaults.set(moneyEnabled, forKey: Keys.moneyEnabled) } }
    var maxSpendGBP: Double { didSet { defaults.set(maxSpendGBP, forKey: Keys.maxSpend) } }
    var generationModel: AIConfig.Model { didSet { defaults.set(generationModel.rawValue, forKey: Keys.generationModel) } }
    var geminiModel: AIConfig.GeminiModel { didSet { defaults.set(geminiModel.rawValue, forKey: Keys.geminiModel) } }
    /// Quests may involve other people (faces are blurred on-device before photos are sent).
    var allowPeople: Bool { didSet { defaults.set(allowPeople, forKey: Keys.allowPeople) } }
    /// Quests or photo challenges.
    var mode: QuestMode { didSet { defaults.set(mode.rawValue, forKey: Keys.mode) } }
    /// Race a countdown (based on difficulty and distance) for bonus points.
    var timeTrial: Bool { didSet { defaults.set(timeTrial, forKey: Keys.timeTrial) } }
    var offerStrongerRecheck: Bool { didSet { defaults.set(offerStrongerRecheck, forKey: Keys.strongRecheck) } }
    var showDebugInfo: Bool { didSet { defaults.set(showDebugInfo, forKey: Keys.debugInfo) } }

    // Debug-only knobs (shown in the debug menu).
    var mockVerdictMode: MockAIProvider.VerdictMode { didSet { defaults.set(mockVerdictMode.rawValue, forKey: Keys.mockVerdict) } }
    var mockInjectInvalidQuest: Bool { didSet { defaults.set(mockInjectInvalidQuest, forKey: Keys.mockInvalid) } }
    var checkDuplicatesForTestPhotos: Bool { didSet { defaults.set(checkDuplicatesForTestPhotos, forKey: Keys.dupTestPhotos) } }
    var skipGeofence: Bool { didSet { defaults.set(skipGeofence, forKey: Keys.skipGeofence) } }
    /// Debug: offer bundled test photos even on a device with a camera.
    var preferTestPhotos: Bool { didSet { defaults.set(preferTestPhotos, forKey: Keys.preferTestPhotos) } }

    var money: MoneySettings { MoneySettings(enabled: moneyEnabled, maxSpendGBP: maxSpendGBP) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Keys.onboarding)
        providerKind = defaults.string(forKey: Keys.provider).flatMap(ProviderKind.init(rawValue:)) ?? Self.defaultProvider
        scope = defaults.string(forKey: Keys.scope).flatMap(QuestScope.init(rawValue:)) ?? .venue
        venueDescription = defaults.string(forKey: Keys.venue) ?? ""
        theme = defaults.string(forKey: Keys.theme).flatMap(QuestTheme.init(rawValue:))
        difficulty = defaults.string(forKey: Keys.difficulty).flatMap(DifficultyPreference.init(rawValue:)) ?? .any
        moneyEnabled = defaults.object(forKey: Keys.moneyEnabled) as? Bool ?? MoneySettings.default.enabled
        maxSpendGBP = defaults.object(forKey: Keys.maxSpend) as? Double ?? MoneySettings.default.maxSpendGBP
        generationModel = defaults.string(forKey: Keys.generationModel).flatMap(AIConfig.Model.init(rawValue:)) ?? AIConfig.generationModel
        geminiModel = defaults.string(forKey: Keys.geminiModel).flatMap(AIConfig.GeminiModel.init(rawValue:)) ?? AIConfig.geminiDefaultModel
        allowPeople = defaults.bool(forKey: Keys.allowPeople)
        mode = defaults.string(forKey: Keys.mode).flatMap(QuestMode.init(rawValue:)) ?? .quest
        timeTrial = defaults.bool(forKey: Keys.timeTrial)
        offerStrongerRecheck = defaults.object(forKey: Keys.strongRecheck) as? Bool ?? true
        #if DEBUG
        showDebugInfo = defaults.object(forKey: Keys.debugInfo) as? Bool ?? true
        #else
        showDebugInfo = defaults.object(forKey: Keys.debugInfo) as? Bool ?? false
        #endif
        mockVerdictMode = defaults.string(forKey: Keys.mockVerdict).flatMap(MockAIProvider.VerdictMode.init(rawValue:)) ?? .auto
        mockInjectInvalidQuest = defaults.bool(forKey: Keys.mockInvalid)
        checkDuplicatesForTestPhotos = defaults.bool(forKey: Keys.dupTestPhotos)
        skipGeofence = defaults.bool(forKey: Keys.skipGeofence)
        preferTestPhotos = defaults.bool(forKey: Keys.preferTestPhotos)
    }

    /// Demo mode in the simulator (saves credit during development); Claude on a real device.
    static var defaultProvider: ProviderKind {
        #if targetEnvironment(simulator)
        return .demo
        #else
        return .claude
        #endif
    }

    func resetAll() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
    }

    private enum Keys {
        static let onboarding = "settings.onboardingComplete"
        static let provider = "settings.provider"
        static let scope = "settings.scope"
        static let venue = "settings.venueDescription"
        static let theme = "settings.theme"
        static let difficulty = "settings.difficulty"
        static let moneyEnabled = "settings.moneyEnabled"
        static let maxSpend = "settings.maxSpendGBP"
        static let generationModel = "settings.generationModel"
        static let geminiModel = "settings.geminiModel"
        static let allowPeople = "settings.allowPeople"
        static let mode = "settings.mode"
        static let timeTrial = "settings.timeTrial"
        static let strongRecheck = "settings.offerStrongerRecheck"
        static let debugInfo = "settings.showDebugInfo"
        static let mockVerdict = "debug.mockVerdictMode"
        static let mockInvalid = "debug.mockInjectInvalidQuest"
        static let dupTestPhotos = "debug.checkDuplicatesForTestPhotos"
        static let skipGeofence = "debug.skipGeofence"
        static let preferTestPhotos = "debug.preferTestPhotos"
        static let all = [onboarding, provider, scope, venue, theme, difficulty, moneyEnabled, maxSpend, generationModel, geminiModel, allowPeople, mode, timeTrial,
                          strongRecheck, debugInfo, mockVerdict, mockInvalid, dupTestPhotos, skipGeofence, preferTestPhotos]
    }
}

extension QuestSettingsFingerprint {
    @MainActor
    init(settings: AppSettings) {
        self.init(scope: settings.scope,
                  venue: settings.venueDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                  theme: settings.theme, difficulty: settings.difficulty,
                  allowPeople: settings.allowPeople, money: settings.money,
                  mode: settings.mode, timeTrial: settings.timeTrial)
    }
}
