import SwiftUI

/// Debug knobs and the AI call counter.
struct DebugMenuView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AIUsageTracker.self) private var tracker
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("This quest", value: "\(tracker.currentQuestCalls.count) calls · \(AIUsageTracker.formatCost(tracker.currentQuestCost))")
                LabeledContent("All time", value: "\(tracker.lifetimeCalls) calls · \(AIUsageTracker.formatCost(tracker.lifetimeCostUSD))")
                Toggle("Show AI cost on quest screens", isOn: $settings.showDebugInfo)
                Button("Reset usage counter") { tracker.resetLifetime() }
            } header: {
                Text("AI usage (estimate)")
            } footer: {
                Text("Estimated from token counts and list prices in AIConfig.swift, plus $0.01 per web search. Your Anthropic console has the real bill.")
            }

            if !tracker.calls.isEmpty {
                Section("Recent calls") {
                    ForEach(tracker.calls.suffix(12).reversed()) { call in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(call.kind.rawValue) · \(call.model)").font(.subheadline.weight(.semibold))
                            Text("in \(call.inputTokens) · out \(call.outputTokens)\(call.webSearches > 0 ? " · \(call.webSearches) searches" : "") · \(AIUsageTracker.formatCost(call.costUSD))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !tracker.lastRejections.isEmpty {
                Section("Last rejected quest (validators)") {
                    ForEach(tracker.lastRejections, id: \.self) { Text($0).font(.caption) }
                }
            }

            Section {
                Picker("Demo verdict", selection: $settings.mockVerdictMode) {
                    ForEach(MockAIProvider.VerdictMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Make first quest attempt break the rules", isOn: $settings.mockInjectInvalidQuest)
            } header: {
                Text("Demo mode")
            } footer: {
                Text("Turn on rule-breaking to watch the money and safety validators reject a quest and regenerate it.")
            }

            Section("Testing") {
                Toggle("Use test photos instead of camera", isOn: $settings.preferTestPhotos)
                Toggle("Check duplicates for test photos", isOn: $settings.checkDuplicatesForTestPhotos)
                Toggle("Skip location check", isOn: $settings.skipGeofence)
                Button("Replay onboarding") { settings.onboardingComplete = false }
                Button("Reset progress & history", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Debug")
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { environment.store.resetProgress() }
        } message: { Text("Deletes points, badges and quest history on this device.") }
    }
}
