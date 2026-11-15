import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0
    @State private var keyEntryProvider: ProviderKind?

    var body: some View {
        ZStack {
            Theme.softGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    intro.tag(0)
                    howItWorks.tag(1)
                    keyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: 3, current: page)
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    if page < 2 {
                        Button("Next") { withAnimation { page += 1 } }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button { keyEntryProvider = .claude } label: { Label("Paste my Claude key", systemImage: "doc.on.clipboard") }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("I have a Gemini key instead") { keyEntryProvider = .gemini }
                            .font(.subheadline.weight(.semibold))
                        Button {
                            settings.providerKind = .demo
                            settings.onboardingComplete = true
                        } label: { Label("Try demo mode", systemImage: "play.circle") }
                            .buttonStyle(SecondaryButtonStyle())
                        Text("Demo mode uses canned quests and verdicts — no key, no cost.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                // Swap the buttons instantly; cross-fading them would overlap mid-animation.
                .transaction { $0.animation = nil }
            }
        }
        .sheet(item: $keyEntryProvider) { provider in
            NavigationStack {
                APIKeyEntryView(provider: provider) {
                    keyEntryProvider = nil
                    settings.onboardingComplete = true
                }
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Theme.asphalt).frame(width: 150, height: 150)
                DetourMark(color: Theme.signal).frame(width: 86, height: 86).offset(x: 3, y: -2)
            }
            Text(AppBrand.name).font(.system(size: 44, weight: .black, design: .rounded))
            Text("Take a little detour. Real-world quests made for exactly where you are.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()
            Text("How it works").font(.largeTitle.weight(.heavy))
            step("hand.tap.fill", "Tap once", "Get a quest for your venue, your street or your city.")
            step("camera.fill", "Snap it", "Complete it and take a photo in the app.")
            step("checkmark.seal.fill", "Get it checked", "An AI referee checks your photo — kindly.")
            step("star.circle.fill", "Level up", "Earn points, keep your streak and collect badges.")
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 50, height: 50)
                .background(Theme.questGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var keyPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 96, height: 96)
                .background(Theme.questGradient, in: Circle())
            Text("Bring your own AI key").font(.title.weight(.heavy)).multilineTextAlignment(.center)
            Text("The app talks to Claude or Gemini directly with your own API key. It's stored only in this iPhone's Keychain. A quest typically costs well under a cent, and Gemini has a free tier.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Link("Get a key at platform.claude.com", destination: AIConfig.apiKeyConsoleURL)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }
}

private struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Theme.questGradient) : AnyShapeStyle(.secondary.opacity(0.3)))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
