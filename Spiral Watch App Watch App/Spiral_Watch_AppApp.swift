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
        hk.onNewSleepData = { [store] in
            Task { await store.refreshFromHealthKit() }
        }
        hk.startObservingNewSleep()
    }
}
