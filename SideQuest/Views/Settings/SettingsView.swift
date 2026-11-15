import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    @State private var keyRefresh = 0
    @State private var keyEntryProvider: ProviderKind?
    @State private var keyToRemove: ProviderKind?
    @State private var showClearedVenue = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $settings.providerKind) {
                        ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
                    }
                    switch settings.providerKind {
                    case .claude:
                        Picker("Quest model", selection: $settings.generationModel) {
                            ForEach(AIConfig.Model.allCases) { Text($0.displayName).tag($0) }
                        }
                    case .gemini:
                        Picker("Model", selection: $settings.geminiModel) {
                            ForEach(AIConfig.GeminiModel.allCases) { Text($0.displayName).tag($0) }
                        }
                    case .demo:
                        EmptyView()
                    }
                    if settings.providerKind != .demo {
                        Toggle("Offer re-check with a stronger model", isOn: $settings.offerStrongerRecheck)
                    }
                    if settings.providerKind != .demo && !APIKeyStore.hasKey(for: settings.providerKind) {
                        Label("Add a \(settings.providerKind == .claude ? "Claude" : "Gemini") key below to use this provider.",
                              systemImage: "key.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.unsure)
                    }
                } header: {
                    Text("AI")
                } footer: {
                    switch settings.providerKind {
                    case .claude:
                        Text("Photos are checked by \(AIConfig.verificationModel.displayName). “Unsure” photos can be re-checked by \(AIConfig.strongVerificationModel.displayName).")
                    case .gemini:
                        Text("Quests and photo checks use \(settings.geminiModel.displayName); venue research uses \(AIConfig.geminiResearchModel.displayName) with Google Search when your key allows it. “Unsure” photos can be re-checked by \(AIConfig.geminiStrongModel.displayName). Gemma models are free-tier only.")
                    case .demo:
                        Text("Demo mode uses canned quests and verdicts. No API key, no cost.")
                    }
                }

                Section {
                    apiKeyRow(.claude, consoleTitle: "Get a key at platform.claude.com", console: AIConfig.apiKeyConsoleURL)
                    apiKeyRow(.gemini, consoleTitle: "Get a key at aistudio.google.com", console: AIConfig.geminiKeyConsoleURL)
                } header: {
                    Text("API keys")
                } footer: {
                    Text("Stored only in this iPhone's Keychain. Never synced, logged or shared.")
                }
                .id(keyRefresh)

                Section {
                    Toggle("Time trial", isOn: $settings.timeTrial)
                        .accessibilityIdentifier("timeTrialToggle")
                } header: {
                    Text("Time trial")
                } footer: {
                    Text("A countdown starts when you accept a quest. Its length depends on the difficulty and how far away the target is (walking pace, or bus/bike pace beyond 2 km). Beat it for +50% points; running out just means no bonus.")
                }

                Section {
                    Toggle("Quests with other people", isOn: $settings.allowPeople)
                } header: {
                    Text("People")
                } footer: {
                    Text("Lets quests ask you to chat with people or get their help. Faces are always blurred on your phone before a photo is checked, and you can blur anything else before sending.")
                }

                Section {
                    Toggle("Quests may include optional spending", isOn: $settings.moneyEnabled.animation())
                    if settings.moneyEnabled {
                        VStack(alignment: .leading) {
                            Text("Max optional spend: £\(Int(settings.maxSpendGBP))")
                            Slider(value: $settings.maxSpendGBP, in: MoneySettings.sliderRange, step: 1) {
                                Text("Max optional spend")
                            } minimumValueLabel: { Text("£0") } maximumValueLabel: { Text("£50") }
                        }
                    }
                } header: {
                    Text("Money")
                } footer: {
                    Text(settings.moneyEnabled
                         ? "Every quest can still be completed for free, and spending never earns extra points."
                         : "Quests never involve spending money.")
                }

                Section("Defaults") {
                    Picker("Scope", selection: $settings.scope) {
                        ForEach(QuestScope.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Theme", selection: $settings.theme) {
                        Text("🎲 Surprise me").tag(QuestTheme?.none)
                        ForEach(QuestTheme.allCases) { Text("\($0.emoji) \($0.title)").tag(QuestTheme?.some($0)) }
                    }
                    Picker("Difficulty", selection: $settings.difficulty) {
                        ForEach(DifficultyPreference.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.scope == .venue {
                        TextField("Venue (one line)", text: $settings.venueDescription)
                    }
                    Button("Forget researched venues") {
                        environment.store.clearVenueCache()
                        showClearedVenue = true
                    }
                }

                Section {
                    NavigationLink("Privacy") { PrivacyNoteView() }
                    NavigationLink("Debug & AI usage") { DebugMenuView() }
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $keyEntryProvider, onDismiss: { keyRefresh += 1 }) { provider in
                NavigationStack { APIKeyEntryView(provider: provider) { keyEntryProvider = nil } }
            }
            .confirmationDialog("Remove this API key?", isPresented: Binding(get: { keyToRemove != nil }, set: { if !$0 { keyToRemove = nil } }),
                                titleVisibility: .visible, presenting: keyToRemove) { provider in
                Button("Remove key", role: .destructive) {
                    try? APIKeyStore.removeKey(for: provider)
                    if settings.providerKind == provider { settings.providerKind = .demo }
                    keyRefresh += 1
                }
            } message: { provider in
                Text("Your \(provider == .claude ? "Claude" : "Gemini") key will be deleted from this iPhone's Keychain.\(settings.providerKind == provider ? " The app will switch to demo mode." : "")")
            }
            .alert("Venue research cleared", isPresented: $showClearedVenue) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your venue will be researched again next time.") }
            .onAppear { keyRefresh += 1 }
        }
    }

    @ViewBuilder
    private func apiKeyRow(_ provider: ProviderKind, consoleTitle: String, console: URL) -> some View {
        let name = provider == .claude ? "Claude" : "Gemini"
        if let key = APIKeyStore.key(for: provider), !key.isEmpty {
            LabeledContent("\(name) key", value: APIKeyStore.masked(key, provider: provider))
            HStack {
                Button("Replace") { keyEntryProvider = provider }
                Spacer()
                Button("Remove", role: .destructive) { keyToRemove = provider }
            }
            .buttonStyle(.borderless)
        } else {
            Button("Add \(name) API key") { keyEntryProvider = provider }
            Link(consoleTitle, destination: console)
        }
    }
}

/// Paste and verify a Claude API key. Shared by onboarding and Settings.
struct APIKeyEntryView: View {
    @Environment(AppSettings.self) private var settings
    var provider: ProviderKind = .claude
    var onSaved: () -> Void

    private var name: String { provider == .claude ? "Claude" : "Gemini" }

    @State private var key = ""
    @State private var isChecking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                SecureField(provider == .claude ? "sk-ant-…" : "AIza…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    if let pasted = UIPasteboard.general.string { key = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            } header: {
                Text("Your \(name) API key")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if provider == .claude {
                        Text("Create one at platform.claude.com → API keys. You pay Anthropic directly for what you use; a quest costs a fraction of a cent.")
                        Link("Open platform.claude.com", destination: AIConfig.apiKeyConsoleURL)
                    } else {
                        Text("Create one in Google AI Studio → Get API key. The free tier costs nothing but has rate limits, and Google may use free-tier prompts and photos to improve its products.")
                        Link("Open aistudio.google.com", destination: AIConfig.geminiKeyConsoleURL)
                    }
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.fail) }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(isChecking ? "Checking…" : "Save key")
                        if isChecking { Spacer(); ProgressView() }
                    }
                }
                .disabled(key.isEmpty || isChecking)
            } footer: {
                Text("Saved only in the iOS Keychain on this device.")
            }
        }
        .navigationTitle("\(name) API key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        error = nil
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard APIKeyStore.looksValid(trimmed, for: provider) else {
            error = provider == .claude
                ? "That doesn't look like a Claude API key. It should start with “sk-ant-”."
                : "That doesn't look like a Gemini API key. Copy the whole key from Google AI Studio."
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            // Both providers' model-list endpoints are free, so this check costs nothing.
            if provider == .claude {
                try await AnthropicClient(apiKey: { trimmed }).validateKey()
            } else {
                try await GeminiClient(apiKey: { trimmed }).validateKey()
            }
            try APIKeyStore.saveKey(trimmed, for: provider)
            key = ""
            settings.providerKind = provider
            Haptics.success()
            onSaved()
        } catch let aiError as AIError {
            error = aiError.errorDescription
        } catch {
            self.error = "Couldn't save the key to the Keychain."
        }
    }
}

struct PrivacyNoteView: View {
    var body: some View {
        List {
            Section {
                Text("\(AppBrand.name) has no server of its own. Nothing about you is stored anywhere except on this iPhone.")
            }
            Section("What gets sent to the AI") {
                Label("Quest context: your scope, theme, the venue line you typed, and the names and categories of nearby places (never your coordinates).", systemImage: "text.bubble")
                Label("Your quest photo, resized, with faces blurred and all location and camera data stripped on your phone before it leaves. If people are in the shot, you see exactly what will be sent and can blur more first.", systemImage: "photo")
                Label("It goes to the provider you picked: Anthropic (Claude) or Google (Gemini), or nowhere at all in demo mode.", systemImage: "arrow.up.forward.app")
                Label("Photo challenges in Nearby/City look up the current weather from Open-Meteo, using your location rounded to about 1 km. The AI only gets a description like “light rain, 11°C”.", systemImage: "cloud.sun")
            }
            Section("What stays on your phone") {
                Label("Your Claude API key (in the iOS Keychain).", systemImage: "key.fill")
                Label("Quest history, thumbnails, points and badges.", systemImage: "book.closed")
                Label("Your precise location, used only to find places and check you're near the quest spot.", systemImage: "location")
            }
            Section("Good to know") {
                Text("Anthropic and Google process API requests under their own terms and privacy policies. On Google's free Gemini tier, Google may use your prompts and photos to improve its products; the paid tier doesn't. Venue research uses the provider's web search for the venue you typed.")
                Text("The AI judges only what's visible in a photo. It can't confirm age, authenticity, price or where a photo was taken.")
            }
        }
        .navigationTitle("Privacy")
    }
}
