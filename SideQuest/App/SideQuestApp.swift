import SwiftUI
import SwiftData

@main
struct SideQuestApp: App {
    private let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        // UI tests start from a clean slate: fresh preferences and an in-memory store.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if isUITesting, let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.set(true, forKey: "debug.preferTestPhotos")
        }
        let container: ModelContainer
        do {
            container = try ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: isUITesting))
        } catch {
            // If the store can't be opened, keep the app usable with an in-memory store.
            container = try! ModelContainer(for: QuestRecord.self, PlayerProfile.self, CachedVenue.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        _environment = State(initialValue: AppEnvironment(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
                .environment(environment.flow)
                .environment(environment.tracker)
                .modelContainer(container)
                .fontDesign(.rounded)
                .tint(Theme.accent)
        }
    }
}

/// Owns the long-lived services.
@MainActor
@Observable
final class AppEnvironment {
    let settings: AppSettings
    let tracker: AIUsageTracker
    let location: LocationService
    let store: ProgressStore
    let flow: QuestFlowModel

    init(context: ModelContext) {
        settings = AppSettings()
        tracker = AIUsageTracker()
        location = LocationService()
        store = ProgressStore(context: context)
        #if DEBUG
        MarketingSeed.apply(settings: settings, store: store)
        #endif
        flow = QuestFlowModel(settings: settings, tracker: tracker, location: location, store: store)
    }
}
