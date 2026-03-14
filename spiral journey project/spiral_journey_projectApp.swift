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
                    // Initialize CloudKit sync
                    setupCloudSync()

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
                    print("[HK] isAuthorized=\(healthKit.isAuthorized)")
                    if healthKit.isAuthorized {
                        // Auto-adjust startDate to cover actual HealthKit data.
                        // This handles the case where startDate = today but all sleep is from yesterday.
                        if let result = await healthKit.importAndAdjustEpoch(days: store.numDays) {
                            print("[HK] imported \(result.episodes.count) episodes")
                            if result.epoch < store.startDate {
                                store.startDate = result.epoch
                            }
                            store.mergeHealthKitEpisodes(result.episodes)
                        } else {
                            print("[HK] importAndAdjustEpoch returned nil")
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

                    // Upload local data to CloudKit now that HealthKit import has populated episodes.
                    let didEnqueue = runCloudMigrationIfNeeded()

                    // If we just enqueued a migration batch, send immediately.
                    // Otherwise CKSyncEngine may defer the upload indefinitely in this session.
                    if didEnqueue {
                        await store.cloudSync?.sendNow()
                    }

                    // Fetch any remote CloudKit changes on launch.
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
                    Task { await store.cloudSync?.fetchNow() }
                }
        }
    }

    // MARK: - CloudKit Setup

    @MainActor
    private func setupCloudSync() {
        // DEBUG: reset migration key so upload runs again — remove before shipping
        UserDefaults.standard.removeObject(forKey: "cloudkit-initial-migration-done-v5")

        // If the local store has no episodes, start fresh so the engine does a full
        // re-fetch from CloudKit instead of returning immediately based on a stale token.
        let freshStart = store.sleepEpisodes.isEmpty
        if freshStart {
            print("[CloudSync] local store empty — using freshStart to re-fetch all CloudKit records")
        }
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
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            print("[CloudSync] migration already done, skipping. episodes=\(store.sleepEpisodes.count)")
            return false
        }
        // Only mark as done if we actually have data to upload.
        // If episodes are empty (HK not yet authorized), skip and retry next launch.
        guard !store.sleepEpisodes.isEmpty else {
            print("[CloudSync] no episodes yet, will retry migration on next launch")
            return false
        }
        print("[CloudSync] starting initial migration: episodes=\(store.sleepEpisodes.count) events=\(store.events.count)")
        for episode in store.sleepEpisodes { sync.enqueueEpisodeSave(episode) }
        for event   in store.events        { sync.enqueueEventSave(event) }
        sync.enqueueSettingsSave(store.currentCloudSettings())
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[CloudSync] migration enqueued")
        return true
    }
}
