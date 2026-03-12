import SwiftUI
import SpiralKit

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
                    WatchConnectivityManager.shared.onDataRequested = {
                        WatchConnectivityManager.shared.sendAnalysis(
                            records: store.records,
                            events: store.events,
                            analysis: store.analysis,
                            language: store.language.localeIdentifier,
                            appearance: store.appearance.rawValue,
                            spiralType: store.spiralType.rawValue,
                            period: store.period
                        )
                    }
                    #endif
                    #if !targetEnvironment(simulator)
                    await healthKit.requestAuthorization()
                    if healthKit.isAuthorized {
                        // Auto-adjust startDate to cover actual HealthKit data.
                        // This handles the case where startDate = today but all sleep is from yesterday.
                        if let result = await healthKit.importAndAdjustEpoch(days: store.numDays) {
                            if result.epoch < store.startDate {
                                store.startDate = result.epoch
                            }
                            store.mergeHealthKitEpisodes(result.episodes)
                        }

                        // Observe HealthKit for new sleep (e.g. Apple Watch session just finished).
                        healthKit.onNewSleepData = {
                            Task {
                                if let result = await healthKit.importAndAdjustEpoch(days: store.numDays) {
                                    if result.epoch < store.startDate {
                                        store.startDate = result.epoch
                                    }
                                    store.mergeHealthKitEpisodes(result.episodes)
                                }
                            }
                        }
                        healthKit.startObservingNewSleep()
                    }
                    #endif
                }
        }
    }
}
