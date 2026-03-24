import CloudKit
import SpiralKit
import os

/// Manages CloudKit sync via CKSyncEngine.
/// Conforms directly to CKSyncEngineDelegate — no intermediary delegate object.
/// All mutable state is isolated to `@MainActor`; the async delegate methods
/// automatically hop to the main actor when called by CKSyncEngine.
@MainActor
final class CloudSyncManager: NSObject, CKSyncEngineDelegate {

    // MARK: - Callbacks (set on MainActor before sync events can fire)

    var onEpisodesFetched: (([SleepEpisode]) -> Void)?
    var onEventsFetched:   (([CircadianEvent]) -> Void)?
    var onSettingsFetched: ((CloudSettings) -> Void)?
    var onEpisodesDeleted: (([UUID]) -> Void)?
    var onEventsDeleted:   (([UUID]) -> Void)?

    // MARK: - Private

    private var engine: CKSyncEngine!
    private let logger = Logger(subsystem: "xaron.spiral-journey-project", category: "CloudSync")
    private let stateURL: URL

    /// Cache of CKRecord objects pending upload, keyed by CKRecord.ID.
    /// Capped at `maxPendingRecords` to prevent unbounded memory growth under poor connectivity.
    private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
    private var pendingOrder: [CKRecord.ID] = [] // FIFO insertion order for eviction
    private static let maxPendingRecords = 200

    // MARK: - Init

    /// - Parameter freshStart: If true, any saved sync state is deleted before initializing the engine.
    init(freshStart: Bool = false) {
        let container = CKContainer(identifier: "iCloud.xaron.spiral-journey-project")

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        // Ensure the Application Support directory exists before writing state.
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        stateURL = appSupport.appendingPathComponent("CKSyncEngineState.dat")

        if freshStart {
            try? FileManager.default.removeItem(at: stateURL)
        }

        let savedState: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data) {
            savedState = decoded
        } else {
            savedState = nil
        }

        super.init()

        // self is now fully initialized — safe to pass as delegate.
        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: savedState,
            delegate: self
        )
        engine = CKSyncEngine(config)

    }

    // MARK: - Enqueue Operations

    func enqueueEpisodeSave(_ episode: SleepEpisode) {
        enqueueRecord(CloudRecordConverter.record(from: episode))
    }

    func enqueueEventSave(_ event: CircadianEvent) {
        enqueueRecord(CloudRecordConverter.record(from: event))
    }

    func enqueueSettingsSave(_ settings: CloudSettings) {
        enqueueRecord(CloudRecordConverter.settingsRecord(from: settings))
    }

    func enqueueEpisodeDelete(id: UUID) {
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudRecordConverter.episodeRecordID(for: id))
        ])
    }

    func enqueueEventDelete(id: UUID) {
        engine.state.add(pendingRecordZoneChanges: [
            .deleteRecord(CloudRecordConverter.eventRecordID(for: id))
        ])
    }

    /// Trigger an immediate fetch (call on app launch / foreground).
    func fetchNow() async {
        do {
            try await engine.fetchChanges()
        } catch {
            logger.error("fetchNow: fetchChanges failed: \(error.localizedDescription)")
        }
    }

    /// Trigger an immediate upload of all pending records.
    func sendNow() async {
        // Tell the engine to create the SpiralData zone before sending records.
        let zone = CKRecordZone(zoneID: CloudRecordConverter.zoneID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])

        do {
            try await engine.sendChanges()
        } catch {
            logger.error("sendNow: sendChanges failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func enqueueRecord(_ record: CKRecord) {
        // Evict oldest pending record (FIFO) if at capacity to prevent unbounded memory growth.
        if pendingRecords.count >= Self.maxPendingRecords, !pendingOrder.isEmpty {
            let oldest = pendingOrder.removeFirst()
            pendingRecords.removeValue(forKey: oldest)
            logger.warning("Pending records at capacity (\(Self.maxPendingRecords)), evicted oldest")
        }
        pendingRecords[record.recordID] = record
        // Update FIFO order: remove if re-enqueued, then append to back
        pendingOrder.removeAll { $0 == record.recordID }
        pendingOrder.append(record.recordID)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            persistState(e.stateSerialization)

        case .fetchedRecordZoneChanges(let e):
            processFetchedChanges(e)

        case .sentRecordZoneChanges(let e):
            processSentChanges(e, syncEngine: syncEngine)

        case .sentDatabaseChanges:
            break

        case .willSendChanges:
            break

        case .didSendChanges:
            break

        case .accountChange(let e):
            handleAccountChange(e)

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let allPending = syncEngine.state.pendingRecordZoneChanges
        let inScope    = allPending.filter { context.options.scope.contains($0) }

        let pending = inScope.isEmpty ? allPending : inScope
        guard !pending.isEmpty else { return nil }

        let snapshot = pendingRecords
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            snapshot[recordID]
        }
    }

    // MARK: - Fetched Changes

    private func processFetchedChanges(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var fetchedEpisodes:   [SleepEpisode]  = []
        var fetchedEvents:     [CircadianEvent] = []
        var fetchedSettings:   CloudSettings?
        var deletedEpisodeIDs: [UUID] = []
        var deletedEventIDs:   [UUID] = []

        for mod in e.modifications {
            switch mod.record.recordType {
            case CloudRecordConverter.episodeType:
                if let ep = CloudRecordConverter.episode(from: mod.record) {
                    fetchedEpisodes.append(ep)
                } else {
                    logger.error("  failed to decode SleepEpisode \(mod.record.recordID.recordName)")
                }
            case CloudRecordConverter.eventType:
                if let ev = CloudRecordConverter.event(from: mod.record) {
                    fetchedEvents.append(ev)
                }
            case CloudRecordConverter.settingsType:
                fetchedSettings = CloudRecordConverter.settings(from: mod.record)
            default:
                logger.warning("  unknown record type: \(mod.record.recordType)")
            }
        }

        for deletion in e.deletions {
            guard let uuid = UUID(uuidString: deletion.recordID.recordName) else { continue }
            switch deletion.recordType {
            case CloudRecordConverter.episodeType:
                deletedEpisodeIDs.append(uuid)
            case CloudRecordConverter.eventType:
                deletedEventIDs.append(uuid)
            default:
                logger.info("  ignoring deletion of unknown type: \(deletion.recordType)")
            }
        }

        // Already on @MainActor — invoke callbacks directly.
        if !fetchedEpisodes.isEmpty   { onEpisodesFetched?(fetchedEpisodes) }
        if !fetchedEvents.isEmpty     { onEventsFetched?(fetchedEvents) }
        if !deletedEpisodeIDs.isEmpty { onEpisodesDeleted?(deletedEpisodeIDs) }
        if !deletedEventIDs.isEmpty   { onEventsDeleted?(deletedEventIDs) }
        if let s = fetchedSettings    { onSettingsFetched?(s) }
    }

    // MARK: - Sent Changes

    private func processSentChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for saved in e.savedRecords {
            pendingRecords.removeValue(forKey: saved.recordID)
            pendingOrder.removeAll { $0 == saved.recordID }
        }
        for failure in e.failedRecordSaves {
            // Remove from pending regardless — we'll re-enqueue only if the client wins.
            pendingRecords.removeValue(forKey: failure.record.recordID)
            pendingOrder.removeAll { $0 == failure.record.recordID }

            if failure.error.code == .serverRecordChanged,
               let serverRecord = failure.error.serverRecord {
                let clientMod = failure.record["modifiedAt"] as? Date ?? .distantPast
                let serverMod = serverRecord["modifiedAt"] as? Date ?? .distantPast
                if clientMod > serverMod {
                    // Client is newer — overwrite server record fields and re-enqueue with correct etag.
                    for key in failure.record.allKeys() { serverRecord[key] = failure.record[key] }
                    pendingRecords[serverRecord.recordID] = serverRecord
                    pendingOrder.append(serverRecord.recordID)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])
                } else {
                    // Server is newer — apply server version to local store.
                    // Already on @MainActor — invoke callbacks directly.
                    switch serverRecord.recordType {
                    case CloudRecordConverter.episodeType:
                        if let ep = CloudRecordConverter.episode(from: serverRecord) { onEpisodesFetched?([ep]) }
                    case CloudRecordConverter.eventType:
                        if let ev = CloudRecordConverter.event(from: serverRecord) { onEventsFetched?([ev]) }
                    case CloudRecordConverter.settingsType:
                        if let s = CloudRecordConverter.settings(from: serverRecord) { onSettingsFetched?(s) }
                    default: break
                    }
                }
            } else {
                logger.error("Failed to save \(failure.record.recordID.recordName): \(failure.error.localizedDescription)")
            }
        }
    }

    // MARK: - Account Changes

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) {
        switch e.changeType {
        case .switchAccounts:
            logger.warning("iCloud account switched — resetting sync state")
            try? FileManager.default.removeItem(at: stateURL)
        case .signIn:
            break
        case .signOut:
            break
        @unknown default:
            break
        }
    }

    // MARK: - State Persistence

    private func persistState(_ s: CKSyncEngine.State.Serialization) {
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to persist sync state: \(error.localizedDescription)")
        }
    }
}
