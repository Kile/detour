import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(QuestFlowModel.self) private var flow
    @Environment(AppSettings.self) private var settings
    @Query private var profiles: [PlayerProfile]
    @State private var showScopeSheet = false
    @State private var presentQuest = false
    @State private var confirmReplace = false

    private var profile: PlayerProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.softGradient.ignoresSafeArea()
                VStack(spacing: 22) {
                    StatsHeader(profile: profile)
                    ModePicker()
                    Spacer(minLength: 0)
                    if let active = flow.activeQuest, !flow.isWorkingOnNewQuest {
                        ContinueQuestCard(active: active) { presentQuest = true }
                            .transition(.scale.combined(with: .opacity))
                    }
                    QuestButton(mode: settings.mode, isWorking: flow.isWorkingOnNewQuest, status: flow.workingStatus) {
                        if settings.scope == .venue && settings.venueDescription.trimmingCharacters(in: .whitespaces).isEmpty {
                            showScopeSheet = true
                        } else if let active = flow.activeQuest {
                            // An offered quest just reopens (no free rerolls); an accepted one asks first.
                            if active.accepted { confirmReplace = true } else { presentQuest = true }
                        } else {
                            flow.requestQuest()
                        }
                    }
                    ScopeChip { showScopeSheet = true }
                    if let error = flow.errorMessage, !presentQuest {
                        ErrorBanner(message: error) { flow.errorMessage = nil }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: flow.activeQuest?.id)
            }
            .navigationTitle(AppBrand.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if flow.isWorkingOnNewQuest {
                    Button("Cancel") { flow.cancelWork() }
                }
            }
            .sheet(isPresented: $showScopeSheet) {
                ScopeSheet()
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $presentQuest) {
                QuestSessionView(isPresented: $presentQuest)
            }
            .onChange(of: flow.phase) { _, phase in
                if phase == .offered && !presentQuest { presentQuest = true }
            }
            .confirmationDialog("Start a new quest?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Discard it and start a new one (−\(Scoring.rerollCost) pts)", role: .destructive) {
                    flow.discard()
                    flow.requestQuest()
                }
                Button("Keep my current quest") { presentQuest = true }
            } message: {
                Text("You're in the middle of “\(flow.activeQuest?.quest.title ?? "a quest")”.")
            }
        }
    }
}

extension QuestFlowModel {
    /// Working on a brand-new quest (not a reroll from the quest card).
    var isWorkingOnNewQuest: Bool {
        if case .working = phase { return activeQuest == nil }
        return false
    }

    var workingStatus: String? {
        switch phase {
        case .working(let status), .verifying(let status): return status
        default: return nil
        }
    }
}

private struct StatsHeader: View {
    var profile: PlayerProfile?

    var body: some View {
        let xp = profile?.xp ?? 0
        let progress = Scoring.levelProgress(xp: xp)
        let streak = Streak.displayed(current: profile?.streak ?? 0, lastCompletionDay: profile?.lastCompletionDay)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.signal.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.02, progress.fraction))
                    .stroke(Theme.signal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("LV").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text("\(progress.level)").font(.title2.weight(.heavy))
                }
            }
            .frame(width: 62, height: 62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(progress.level), \(progress.intoLevel) of \(progress.levelSize) XP to next level")

            VStack(alignment: .leading, spacing: 4) {
                Text(Scoring.title(forLevel: progress.level)).font(.headline)
                Text("\(progress.intoLevel) / \(progress.levelSize) XP to level \(progress.level + 1)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label("\(profile?.points ?? 0)", systemImage: "star.circle.fill")
                    .foregroundStyle(Theme.gold)
                    .accessibilityLabel("\(profile?.points ?? 0) points")
                Label("\(streak)", systemImage: "flame.fill")
                    .foregroundStyle(streak > 0 ? .orange : .secondary)
                    .accessibilityLabel("\(streak) day streak")
            }
            .font(.headline.monospacedDigit())
        }
        .card()
        .padding(.top, 8)
    }
}

/// The one big button.
private struct QuestButton: View {
    var mode: QuestMode
    var isWorking: Bool
    var status: String?
    var action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.questGradient)
                    .shadow(color: Theme.asphalt.opacity(0.35), radius: pulse ? 30 : 16, y: 10)
                // A dashed "planned route" ring around the button, echoing the logo.
                Circle()
                    .strokeBorder(Theme.markOnPrimary.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 9]))
                    .padding(12)
                VStack(spacing: 10) {
                    if isWorking {
                        ProgressView().tint(Theme.onPrimary).scaleEffect(1.6)
                        Text(status ?? "Working…")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    } else {
                        Text(mode.buttonTitle)
                            .font(mode == .quest ? .largeTitle.weight(.heavy) : .title.weight(.heavy))
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                    }
                }
                .foregroundStyle(Theme.onPrimary)
            }
            .frame(width: 250, height: 250)
            .scaleEffect(pulse && !isWorking ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityIdentifier("questButton")
        .accessibilityLabel(isWorking ? (status ?? "Working") : mode.accessibilityTitle)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Shows the current scope; tap to change scope, venue, theme and difficulty.
struct ScopeChip: View {
    @Environment(AppSettings.self) private var settings
    var action: () -> Void

    private var label: String {
        switch settings.scope {
        case .venue:
            let venue = settings.venueDescription.trimmingCharacters(in: .whitespaces)
            return venue.isEmpty ? "Venue: tap to set" : "Venue: \(venue)"
        case .nearby: return "Nearby · ~1 km on foot"
        case .city: return "City"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: settings.scope.symbol)
                Text(label).lineLimit(1)
                if settings.difficulty != .any { Text(settings.difficulty.title).foregroundStyle(.secondary) }
                if let theme = settings.theme { Text(theme.emoji) }
                if settings.allowPeople { Image(systemName: "person.2.fill").foregroundStyle(.secondary) }
                if settings.timeTrial { Image(systemName: "stopwatch").foregroundStyle(.secondary) }
                if settings.moneyEnabled { Text("£\(Int(settings.maxSpendGBP))").foregroundStyle(.secondary) }
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scopeChip")
        .accessibilityHint("Change where and what kind of quest you get")
    }
}

private struct ContinueQuestCard: View {
    var active: ActiveQuest
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: active.accepted ? "flag.checkered" : "envelope.open.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(active.accepted ? "Quest in progress" : "Quest waiting for you")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(active.quest.title).font(.headline).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct ErrorBanner: View {
    var message: String
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.fail)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(Theme.fail.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Quests or photo challenges, right above the big button.
private struct ModePicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(QuestMode.allCases) { mode in
                let selected = settings.mode == mode
                Button {
                    withAnimation(.snappy) { settings.mode = mode }
                    Haptics.tap()
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? Theme.onPrimary : Color.primary)
                        .background {
                            Capsule().fill(selected ? AnyShapeStyle(Theme.questGradient) : AnyShapeStyle(Color.clear))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mode-\(mode.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
    }
}
