import SwiftUI

/// The user-facing name and mark. Renaming the app = change these (and CFBundleDisplayName in project.yml).
/// Masters live in Design/brand/.
enum AppBrand {
    static let name = "Detour"
    /// The D-route mark (vector template image in the asset catalog, tinted by the view).
    static let mark = "DetourMark"
    /// The same mark at tab-bar size (26 pt), for tab items and map pins.
    static let glyph = "DetourGlyph"
}

/// Brand palette: asphalt (#1E2233) and signal orange (#FF6B2C), with cream (#FFF6EA) for text on asphalt.
/// Light mode puts the orange mark on asphalt; dark mode flips to asphalt on orange so buttons stay visible.
enum Theme {
    /// Text-safe orange for links and highlights (deeper in light mode for contrast on white).
    static let accent = Color("AccentColor")
    /// The brand orange itself, for marks and fills.
    static let signal = Color(red: 1.0, green: 0.42, blue: 0.173)
    static let asphalt = Color(red: 0.118, green: 0.133, blue: 0.2)
    /// Big button, primary buttons, selected chips and badges.
    static let primarySurface = Color("PrimarySurface")
    /// Text and icons on `primarySurface`.
    static let onPrimary = Color("OnPrimary")
    /// The D mark on `primarySurface`.
    static let markOnPrimary = Color("MarkOnPrimary")
    /// Kept as a gradient-shaped style so call sites stay simple; it's a near-solid asphalt (or orange in dark mode).
    static let questGradient = LinearGradient(colors: [primarySurface.opacity(0.92), primarySurface],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Calm page background: a faint warm wash, no purple.
    static let softGradient = LinearGradient(colors: [signal.opacity(0.09), signal.opacity(0.015)],
                                             startPoint: .top, endPoint: .bottom)
    static let pass = Color(red: 0.16, green: 0.72, blue: 0.42)
    static let unsure = Color(red: 0.98, green: 0.66, blue: 0.12)
    static let fail = Color(red: 0.92, green: 0.3, blue: 0.3)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.2)
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}

/// The pinned button bar at the bottom of a screen. Solid, so scrolled content doesn't show through,
/// with a soft shadow on top. Attach with `.safeAreaInset(edge: .bottom, spacing: 0)` so the scroll view
/// stops above it.
struct BottomBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    Rectangle().fill(.background)
                    Theme.signal.opacity(0.015)   // matches the bottom of `softGradient`
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
    func bottomBar() -> some View { modifier(BottomBar()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.questGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Five little stars for difficulty.
struct DifficultyStars: View {
    var difficulty: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= difficulty ? "star.fill" : "star")
                    .foregroundStyle(index <= difficulty ? Theme.gold : .secondary.opacity(0.4))
            }
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Difficulty \(difficulty) of 5")
    }
}

/// A small pill label.
struct Pill: View {
    var text: String
    var symbol: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

/// The small "AI calls / cost" readout shown when debug info is on.
struct AICostBadge: View {
    @Environment(AIUsageTracker.self) private var tracker
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.showDebugInfo {
            Label("\(tracker.currentQuestCalls.count) AI call\(tracker.currentQuestCalls.count == 1 ? "" : "s") · est. \(AIUsageTracker.formatCost(tracker.currentQuestCost))",
                  systemImage: "cpu")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Debug: \(tracker.currentQuestCalls.count) AI calls this quest")
        }
    }
}

/// The Detour mark, drawn from the vector asset.
struct DetourMark: View {
    var color: Color = Theme.signal

    var body: some View {
        Image(AppBrand.mark)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
