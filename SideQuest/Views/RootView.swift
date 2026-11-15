import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if settings.onboardingComplete {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: settings.onboardingComplete)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Quest", image: AppBrand.glyph) }
            HistoryView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
