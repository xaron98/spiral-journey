import SwiftUI
import SwiftData
import SpiralKit

@main
struct spiral_journey_projectApp: App {

    @State private var store = SpiralStore()
    @State private var healthKit = HealthKitManager.shared
    @State private var calendarManager = CalendarManager.shared
    @State private var llmService = LLMService()
    @State private var dnaService = SleepDNAService()
    @State private var aiService = OnDeviceAIService()
    @State private var watchBridge: WatchSyncBridge?

    @State private var modelContainer: ModelContainer = {
        let allModels: [any PersistentModel.Type] = [
            SDSleepEpisode.self,
            SDCircadianEvent.self,
            SDPredictionResult.self,
            SDCoachMessage.self,
            SDUserGoal.self,
            SDPredictionMetrics.self,
            SDTrainingMetrics.self,
            SDSleepDNASnapshot.self,
            SDSleepBLOSUM.self,
            SDQuestionnaireResponse.self,
            SDDreamEntry.self
        ]

        // Local-only: explicitly disable CloudKit (CKSyncEngine handles sync separately).
        // Without cloudKitDatabase: .none, SwiftData auto-detects the CloudKit entitlement
        // and requires all attributes to be optional — which we don't want.
        let schema = Schema(allModels)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            #if DEBUG
            print("[SwiftData] Container failed: \(error). Retrying with fresh store…")
            #endif
            try? FileManager.default.removeItem(at: config.url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                #if DEBUG
                print("[SwiftData] Failed after reset: \(error). Falling back to in-memory store.")
                #endif
                let inMemoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                // Last resort: in-memory container so the app can still launch.
                // SwiftData features will work for the session but won't persist.
                // swiftlint:disable:next force_try
                return try! ModelContainer(for: schema, configurations: [inMemoryConfig])
            }
        }
    }()

    init() {
        // Register background processing tasks before the first frame.
        // Must happen in init(), not in .task{}, because BGTaskScheduler
        // requires registration before the app finishes launching.
        BackgroundTaskManager.registerTasks(
            store: store,
            modelContainer: modelContainer,
            dnaService: dnaService
        )

        // Allow notifications to show as banners while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(healthKit)
                .environment(calendarManager)
                .environment(llmService)
                .environment(dnaService)
                .environment(aiService)
                .environment(\.locale, Locale(identifier: store.language.localeIdentifier))
                .environment(\.languageBundle, languageBundle(for: store.language.localeIdentifier))
                .modelContainer(modelContainer)
                .task {
                    // ⓪ Schedule background tasks
                    BackgroundTaskManager.scheduleRetrainIfNeeded()
                    BackgroundTaskManager.scheduleDNARefresh()

                    // ① Let the first frame render before doing any work.
                    //    Without this, the UI appears frozen until the HealthKit
                    //    permission dialog pops up.
                    await Task.yield()

                    // Clean up stale CSV export directories from previous sessions.
                    DataExporter.cleanupOldExports()

                    // Wire up SwiftData context so SpiralStore can read from it.
                    store.configure(with: modelContainer.mainContext)

                    // Clean up duplicate predictions (one-time migration)
                    store.deduplicatePredictionHistory()

                    // ①½ Migrate UserDefaults/JSON data to SwiftData (one-time).
                    DataMigrationService.migrateIfNeeded(store: store, container: modelContainer)

                    // ①¾ Enforce data retention policies (trim old chat/metrics).
                    DataRetentionService.enforce(context: modelContainer.mainContext)

                    // ①⅞ Load cached SleepDNA profile from SwiftData.
                    dnaService.loadCachedProfile(context: modelContainer.mainContext)
                    // Seed the store's dnaProfile for prediction blending.
                    store.dnaProfile = dnaService.latestProfile

                    // Initialize Watch sync bridge for App Group UserDefaults.
                    watchBridge = WatchSyncBridge(appGroupID: SpiralStore.appGroupID)

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
                                // Fast incremental merge — only fetches last 3 days
                                // and adds episodes not yet in the store.
                                let knownIDs = Set(store.sleepEpisodes.compactMap(\.healthKitSampleID))
                                let newEpisodes = await healthKit.fetchRecentNewEpisodes(
                                    epoch: store.startDate, knownIDs: knownIDs)
                                if !newEpisodes.isEmpty {
                                    store.mergeHealthKitEpisodes(newEpisodes)
                                }
                            }
                        }
                        healthKit.startObservingNewSleep()

                        // Primary live update: anchored object query delivers new
                        // samples directly without polling. More reliable than
                        // HKObserverQuery for Watch → iPhone sync.
                        healthKit.startAnchoredSleepQuery(epoch: store.startDate) { newEpisodes in
                            store.mergeHealthKitEpisodes(newEpisodes)
                        }
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
                            // Fast path: incremental merge of last 3 days.
                            store.isSyncingHealthKit = true
                            let knownIDs = Set(store.sleepEpisodes.compactMap(\.healthKitSampleID))
                            let newEpisodes = await healthKit.fetchRecentNewEpisodes(
                                epoch: store.startDate, knownIDs: knownIDs)
                            if !newEpisodes.isEmpty {
                                store.mergeHealthKitEpisodes(newEpisodes)
                            }
                            // Refresh health profiles + auto-import events
                            await store.refreshHealthProfiles()

                            // Retry ladder: 5s, 15s, 30s — Watch Bluetooth transfer can be slow
                            if newEpisodes.isEmpty {
                                for delay in [5, 15, 30] {
                                    try? await Task.sleep(for: .seconds(delay))
                                    let retryIDs = Set(store.sleepEpisodes.compactMap(\.healthKitSampleID))
                                    let retryEpisodes = await healthKit.fetchRecentNewEpisodes(
                                        epoch: store.startDate, knownIDs: retryIDs)
                                    if !retryEpisodes.isEmpty {
                                        store.mergeHealthKitEpisodes(retryEpisodes)
                                        break // got data, stop retrying
                                    }
                                }
                            }
                            store.isSyncingHealthKit = false
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
        guard store.cloudSyncConsent else { return }
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
