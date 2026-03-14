import SwiftUI
import SpiralKit

@main
struct spiral_journey_projectApp: App {

    @State private var store = SpiralStore()
    @State private var healthKit = HealthKitManager.shared
    @State private var calendarManager = CalendarManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(healthKit)
                .environment(calendarManager)
                .environment(\.locale, Locale(identifier: store.language.localeIdentifier))
                .environment(\.languageBundle, languageBundle(for: store.language.localeIdentifier))
                .task {
                    // ① Let the first frame render before doing any work.
                    //    Without this, the UI appears frozen until the HealthKit
                    //    permission dialog pops up.
                    await Task.yield()

                    // Receive events and episodes logged on the Apple Watch
                    #if os(iOS)
                    WatchConnectivityManager.shared.onEventReceived = { event in
                        store.addEvent(event)
                    }
                    WatchConnectivityManager.shared.onEpisodeReceived = { episode in
                        store.mergeHealthKitEpisodes([episode])
                    }
                    WatchConnectivityManager.shared.onDataRequested = {
                        Task {
                            // Import fresh HealthKit data before pushing to Watch,
                            // so the Watch sees sleep recorded since the last push.
                            #if !targetEnvironment(simulator)
                            if healthKit.isAuthorized {
                                if let result = await healthKit.importAndAdjustEpoch() {
                                    store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                }
                            }
                            #endif
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
                    }
                    #endif

                    // ② Request HealthKit authorization (shows permission dialog).
                    #if !targetEnvironment(simulator)
                    await healthKit.requestAuthorization()
                    #endif

                    // ③ Initialize CloudKit while the user has just responded to
                    //    the HealthKit dialog — perceived latency is near zero.
                    setupCloudSync()

                    // ④ Import HealthKit data + CloudKit fetch — interleaved on the
                    //    main actor so each `await` yields and the UI stays responsive.
                    #if !targetEnvironment(simulator)
                    if healthKit.isAuthorized {
                        if let result = await healthKit.importAndAdjustEpoch() {
                            store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                        }

                        healthKit.onNewSleepData = {
                            Task {
                                if let result = await healthKit.importAndAdjustEpoch() {
                                    store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                }
                            }
                        }
                        healthKit.startObservingNewSleep()
                    }
                    #endif

                    // ⑤ CloudKit migration + fetch.
                    let didEnqueue = runCloudMigrationIfNeeded()
                    if didEnqueue {
                        await store.cloudSync?.sendNow()
                    }
                    await store.cloudSync?.fetchNow()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: {
                        #if os(macOS)
                        return NSApplication.willBecomeActiveNotification
                        #else
                        return UIApplication.willEnterForegroundNotification
                        #endif
                    }())
                ) { _ in
                    Task {
                        // Re-import HealthKit on every foreground so Watch sleep
                        // recorded while the app was backgrounded appears immediately.
                        #if !targetEnvironment(simulator)
                        if healthKit.isAuthorized {
                            if let result = await healthKit.importAndAdjustEpoch() {
                                store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                            }
                        }
                        #endif
                        await store.cloudSync?.fetchNow()
                    }
                }
        }
    }

    // MARK: - CloudKit Setup

    @MainActor
    private func setupCloudSync() {
        // If the local store has no episodes, start fresh so the engine does a full
        // re-fetch from CloudKit instead of returning immediately based on a stale token.
        let freshStart = store.sleepEpisodes.isEmpty
        let sync = CloudSyncManager(freshStart: freshStart)
        store.cloudSync = sync

        sync.onEpisodesFetched = { [store] episodes in
            store.mergeCloudEpisodes(episodes)
        }
        sync.onEventsFetched = { [store] events in
            store.mergeCloudEvents(events)
        }
        sync.onSettingsFetched = { [store] settings in
            store.applyCloudSettings(settings)
        }
        sync.onEpisodesDeleted = { [store] ids in
            store.applyCloudDeletions(episodeIDs: ids, eventIDs: [])
        }
        sync.onEventsDeleted = { [store] ids in
            store.applyCloudDeletions(episodeIDs: [], eventIDs: ids)
        }
    }

    /// Upload all local data to CloudKit. Called after HealthKit import so episodes are populated.
    /// Returns true if records were enqueued (caller should then call sendNow()).
    @MainActor
    @discardableResult
    private func runCloudMigrationIfNeeded() -> Bool {
        guard let sync = store.cloudSync else { return false }
        // v5: key renamed to force re-upload with episodes already populated.
        let migrationKey = "cloudkit-initial-migration-done-v5"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return false }
        // Only mark as done if we actually have data to upload.
        // If episodes are empty (HK not yet authorized), skip and retry next launch.
        guard !store.sleepEpisodes.isEmpty else { return false }
        for episode in store.sleepEpisodes { sync.enqueueEpisodeSave(episode) }
        for event   in store.events        { sync.enqueueEventSave(event) }
        sync.enqueueSettingsSave(store.currentCloudSettings())
        UserDefaults.standard.set(true, forKey: migrationKey)
        return true
    }
}
