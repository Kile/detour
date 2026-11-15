import SwiftUI

struct ResultView: View {
    @Environment(QuestFlowModel.self) private var flow
    @State private var shownPoints = 0
    @State private var showConfetti = false
    @State private var appeared = false

    var body: some View {
        if let verdict = flow.verdict {
            ZStack {
                Theme.softGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        banner(verdict)
                        if let outcome = flow.outcome { rewards(outcome) }
                        criteria(verdict)
                        Text("The AI only checks what's visible in your photo. It can't confirm age, authenticity, price or location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        if let error = flow.errorMessage {
                            ErrorBanner(message: error) { flow.errorMessage = nil }
                        }
                        AICostBadge()
                    }
                    .padding(20)
                }
                if showConfetti { ConfettiView().allowsHitTesting(false).ignoresSafeArea() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions(verdict) }
            .overlay { if flow.isBusy { busy } }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { celebrateIfNeeded() }
            .onChange(of: flow.outcome) { _, _ in celebrateIfNeeded() }
        }
    }

    // MARK: Sections

    private func banner(_ verdict: Verdict) -> some View {
        let style = Self.style(for: verdict.verdict)
        return VStack(spacing: 12) {
            if let photo = flow.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: style.symbol)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white, style.color)
                            .padding(10)
                            .scaleEffect(appeared ? 1 : 0.2)
                            .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.15), value: appeared)
                    }
            }
            if flow.photos.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(flow.photos.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .accessibilityLabel("\(flow.photos.count) photos checked")
            }
            Text(flow.passedOnBenefitOfDoubt ? "Counted! Benefit of the doubt 🙌"
                 : (verdict.verdict == .pass && flow.activeQuest?.quest.isPhotoChallenge == true ? "Great shot! 📸" : style.title))
                .font(.title.weight(.heavy))
                .multilineTextAlignment(.center)
            Text(verdict.feedback)
                .font(.body)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Pill(text: "Confidence \(Int((verdict.confidence * 100).rounded()))%", symbol: "gauge.with.dots.needle.50percent", tint: style.color)
                if verdict.recheckedWithStrongerModel == true {
                    Pill(text: "Re-checked", symbol: "eye.fill", tint: .purple)
                }
            }
        }
        .card()
        .onAppear { appeared = true }
    }

    private func rewards(_ outcome: CompletionOutcome) -> some View {
        VStack(spacing: 10) {
            Text("+\(shownPoints)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText(value: Double(shownPoints)))
                .accessibilityLabel("\(outcome.pointsAwarded) points earned")
            Text("points · \(outcome.totalPoints) total").font(.subheadline).foregroundStyle(.secondary)
            // One centred row when it fits, otherwise stacked.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { rewardPills(outcome) }.fixedSize()
                VStack(spacing: 6) { rewardPills(outcome) }
            }
            ForEach(outcome.newBadges) { badge in
                HStack(spacing: 10) {
                    Image(systemName: badge.symbol).font(.title2).foregroundStyle(Theme.gold)
                    VStack(alignment: .leading) {
                        Text("New badge: \(badge.title)").font(.headline)
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func criteria(_ verdict: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Checklist", systemImage: "checklist").font(.headline).foregroundStyle(Theme.accent)
            ForEach(verdict.criteria) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.met ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .foregroundStyle(item.met ? Theme.pass : Theme.unsure)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.criterion).font(.subheadline.weight(.semibold))
                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.met ? "Looks met" : "Not clear"): \(item.criterion). \(item.reason)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder private func actions(_ verdict: Verdict) -> some View {
        VStack(spacing: 10) {
            if flow.outcome != nil {
                Button { flow.finish() } label: { Label("Collect & continue", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            } else if verdict.verdict == .unsure {
                Button { flow.acceptUnsure() } label: { Label("Count it!", systemImage: "hand.thumbsup.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: 10) {
                    if flow.triesLeft > 0 {
                        Button { flow.retake() } label: { Label("Retake", systemImage: "camera.rotate") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if flow.canRecheckWithStrongerModel {
                        Button { flow.recheckWithStrongerModel() } label: { Label("Re-check", systemImage: "eye") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else if flow.triesLeft > 0 {
                Button { flow.tryAnotherPhoto() } label: { Label("Try another photo", systemImage: "camera.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                HStack {
                    Text(flow.triesLeft == 1 ? "1 try left" : "\(flow.triesLeft) tries left")
                        .foregroundStyle(.secondary)
                    Spacer()
                    giveUpButton
                }
                .font(.subheadline)
            } else {
                // Out of tries: another one costs points, and more each time.
                Button { flow.buyAnotherTry() } label: {
                    Label("Buy another try · \(flow.nextTryPrice) pts", systemImage: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!flow.canAffordAnotherTry)
                .opacity(flow.canAffordAnotherTry ? 1 : 0.45)
                .accessibilityIdentifier("buyAnotherTry")
                .accessibilityHint("Spends \(flow.nextTryPrice) of your \(flow.points) points. Each extra try costs more than the last.")
                HStack {
                    Text(flow.canAffordAnotherTry ? "No free tries left · you have \(flow.points) pts"
                                                  : "You need \(flow.nextTryPrice) pts · you have \(flow.points)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    giveUpButton
                }
                .font(.subheadline)
            }
        }
        .bottomBar()
        .disabled(flow.isBusy)
    }

    private var giveUpButton: some View {
        Button(role: .destructive) { flow.abandon() } label: { Text("Give up") }
            .accessibilityLabel("Give up this quest")
    }

    private var busy: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().scaleEffect(1.5)
                Text(flow.workingStatus ?? "Checking…").font(.headline)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder private func rewardPills(_ outcome: CompletionOutcome) -> some View {
        if outcome.timeBonus > 0 {
            Pill(text: "Beat the clock +\(outcome.timeBonus)", symbol: "stopwatch.fill", tint: Theme.gold)
        }
        if outcome.leveledUp {
            Pill(text: "Level \(outcome.newLevel)!", symbol: "arrow.up.circle.fill", tint: Theme.gold)
        }
        Pill(text: "\(outcome.streak)-day streak", symbol: "flame.fill", tint: .orange)
    }

    private func celebrateIfNeeded() {
        guard let outcome = flow.outcome, shownPoints == 0 else { return }
        showConfetti = true
        Haptics.celebrate()
        let steps = 20
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(step) * 0.04) {
                withAnimation(.snappy) { shownPoints = outcome.pointsAwarded * step / steps }
            }
        }
    }

    static func style(for outcome: Verdict.Outcome) -> (title: String, symbol: String, color: Color) {
        switch outcome {
        case .pass: return ("Quest complete! 🎉", "checkmark.seal.fill", Theme.pass)
        case .unsure: return ("Hmm, almost…", "questionmark.circle.fill", Theme.unsure)
        case .fail: return ("Not quite!", "arrow.uturn.backward.circle.fill", Theme.fail)
        }
    }
}

/// Lightweight confetti burst.
struct ConfettiView: View {
    private struct Piece {
        var x: Double, delay: Double, speed: Double, spin: Double, size: Double, drift: Double
        var color: Color
    }

    @State private var start = Date()
    private let pieces: [Piece] = (0..<70).map { _ in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.6), speed: .random(in: 0.35...0.8),
              spin: .random(in: 2...8), size: .random(in: 6...12), drift: .random(in: -40...40),
              color: [Theme.signal, Theme.asphalt, Theme.gold, Theme.signal.opacity(0.6), Color(red: 0.36, green: 0.42, blue: 0.6)].randomElement()!)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let progress = (t - piece.delay) * piece.speed
                    guard progress > 0, progress < 1.4 else { continue }
                    let x = piece.x * size.width + sin(progress * 6) * piece.drift
                    let y = -20 + progress * (size.height + 40)
                    var pieceContext = context
                    pieceContext.translateBy(x: x, y: y)
                    pieceContext.rotate(by: .radians(progress * piece.spin))
                    pieceContext.opacity = progress > 1.1 ? max(0, 1.4 - progress) / 0.3 : 1
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    pieceContext.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}
