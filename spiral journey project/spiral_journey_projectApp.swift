import SwiftUI

@main
struct spiral_journey_projectApp: App {

    @State private var store = SpiralStore()
    @State private var healthKit = HealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(healthKit)
                .environment(\.locale, Locale(identifier: store.language.localeIdentifier))
                .environment(\.languageBundle, languageBundle(for: store.language.localeIdentifier))
                .task {
                    // Receive events and episodes logged on the Apple Watch
                    #if os(iOS)
                    WatchConnectivityManager.shared.onEventReceived = { event in
                        store.addEvent(event)
                    }
                    WatchConnectivityManager.shared.onEpisodeReceived = { episode in
                        store.mergeHealthKitEpisodes([episode])
                    }
                    #endif
                    #if !targetEnvironment(simulator)
                    await healthKit.requestAuthorization()
                    if healthKit.isAuthorized {
                        let episodes = await healthKit.fetchRecentSleepEpisodes(days: store.numDays)
                        store.mergeHealthKitEpisodes(episodes)
                    }
                    #endif
                }
        }
    }
}
