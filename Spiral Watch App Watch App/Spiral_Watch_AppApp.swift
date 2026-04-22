import SwiftUI

@main
struct SpiralWatchApp: App {

    @State private var store = WatchStore()

    private var colorScheme: ColorScheme {
        // On watchOS, "system" means dark (Watch is always OLED dark by default)
        store.appearance == "light" ? .light : .dark
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(store)
                .environment(\.locale, Locale(identifier: store.language))
                .environment(\.languageBundle, languageBundle(for: store.language))
                .environment(\.colorScheme, colorScheme)
                .preferredColorScheme(colorScheme)
                .task { await setupHealthKit() }
        }
    }

    @MainActor
    private func setupHealthKit() async {
        let hk = WatchHealthKitManager.shared
        await hk.requestAuthorization()
        guard hk.isAuthorized else { return }
        // Pull current data immediately, then keep watching for new samples.
        await store.refreshFromHealthKit()

        // Debounced callback — HealthKit can fire multiple times rapidly.
        // Only refresh once per 30 seconds to save battery.
        var lastRefresh = Date()
        hk.onNewSleepData = { [store] in
            let now = Date()
            guard now.timeIntervalSince(lastRefresh) > 30 else { return }
            lastRefresh = now
            Task { await store.refreshFromHealthKit() }
        }

        // Use ONLY anchored query (not both observer + anchored — that doubles callbacks)
        hk.startAnchoredSleepQuery()
    }
}
