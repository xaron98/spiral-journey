import CloudKit
import SpiralKit
import os

/// Manages CloudKit sync via CKSyncEngine.
/// Conforms directly to CKSyncEngineDelegate — no intermediary delegate object.
final class CloudSyncManager: NSObject, CKSyncEngineDelegate, @unchecked Sendable {

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
    private var pendingRecords: [CKRecord.ID: CKRecord] = [:]

    // MARK: - Init

    /// - Parameter freshStart: If true, any saved sync state is deleted before initializing the engine.
    init(freshStart: Bool = false) {
        let container = CKContainer(identifier: "iCloud.xaron.spiral-journey-project")

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
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

        if freshStart {
            logger.info("init: freshStart=true — deleted stale sync state for full re-fetch")
        }
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
        logger.info("fetchNow: starting fetchChanges")
        do {
            try await engine.fetchChanges()
            logger.info("fetchNow: fetchChanges completed")
        } catch {
            logger.error("fetchNow: fetchChanges failed: \(error.localizedDescription)")
        }
    }

    /// Trigger an immediate upload of all pending records.
    func sendNow() async {
        // Tell the engine to create the SpiralData zone before sending records.
        let zone = CKRecordZone(zoneID: CloudRecordConverter.zoneID)
        engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])

        let pendingDB = engine.state.pendingDatabaseChanges.count
        let pendingRZ = engine.state.pendingRecordZoneChanges.count
        logger.info("sendNow: pendingDatabaseChanges=\(pendingDB) pendingRecordZoneChanges=\(pendingRZ) inMemoryRecords=\(self.pendingRecords.count)")

        do {
            try await engine.sendChanges()
            logger.info("sendNow: sendChanges completed. pendingRZ after=\(self.engine.state.pendingRecordZoneChanges.count)")
        } catch {
            logger.error("sendNow: sendChanges failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func enqueueRecord(_ record: CKRecord) {
        pendingRecords[record.recordID] = record
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            persistState(e.stateSerialization)

        case .fetchedRecordZoneChanges(let e):
            await processFetchedChanges(e)

        case .sentRecordZoneChanges(let e):
            logger.info("sentRecordZoneChanges: saved=\(e.savedRecords.count) failed=\(e.failedRecordSaves.count)")
            processSentChanges(e, syncEngine: syncEngine)

        case .sentDatabaseChanges(let e):
            logger.info("sentDatabaseChanges: savedZones=\(e.savedZones.count) failedZoneSaves=\(e.failedZoneSaves.count)")

        case .willSendChanges:
            logger.info("willSendChanges: engine about to send")

        case .didSendChanges:
            logger.info("didSendChanges: engine finished sending")

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
        logger.info("nextBatch: allPending=\(allPending.count) inScope=\(inScope.count)")

        let pending = inScope.isEmpty ? allPending : inScope
        guard !pending.isEmpty else {
            logger.info("nextBatch: nothing to send, returning nil")
            return nil
        }

        let snapshot = pendingRecords
        logger.info("nextBatch: building batch for \(pending.count) changes, snapshot=\(snapshot.count)")

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            snapshot[recordID]
        }
    }

    // MARK: - Fetched Changes

    private func processFetchedChanges(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        var fetchedEpisodes:   [SleepEpisode]  = []
        var fetchedEvents:     [CircadianEvent] = []
        var fetchedSettings:   CloudSettings?
        var deletedEpisodeIDs: [UUID] = []
        var deletedEventIDs:   [UUID] = []

        logger.info("processFetchedChanges: \(e.modifications.count) modifications, \(e.deletions.count) deletions")

        for mod in e.modifications {
            logger.info("  record type=\(mod.record.recordType) id=\(mod.record.recordID.recordName)")
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
            if let uuid = UUID(uuidString: deletion.recordID.recordName) {
                deletedEpisodeIDs.append(uuid)
                deletedEventIDs.append(uuid)
            }
        }

        logger.info("processFetchedChanges: delivering \(fetchedEpisodes.count) episodes, \(fetchedEvents.count) events")
        await MainActor.run { [weak self] in
            guard let self else { return }
            if !fetchedEpisodes.isEmpty   { onEpisodesFetched?(fetchedEpisodes) }
            if !fetchedEvents.isEmpty     { onEventsFetched?(fetchedEvents) }
            if !deletedEpisodeIDs.isEmpty { onEpisodesDeleted?(deletedEpisodeIDs) }
            if !deletedEventIDs.isEmpty   { onEventsDeleted?(deletedEventIDs) }
            if let s = fetchedSettings    { onSettingsFetched?(s) }
        }
    }

    // MARK: - Sent Changes

    private func processSentChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for saved in e.savedRecords {
            pendingRecords.removeValue(forKey: saved.recordID)
        }
        for failure in e.failedRecordSaves {
            if failure.error.code == .serverRecordChanged,
               let serverRecord = failure.error.serverRecord {
                let clientMod = failure.record["modifiedAt"] as? Date ?? .distantPast
                let serverMod = serverRecord["modifiedAt"] as? Date ?? .distantPast
                if clientMod > serverMod {
                    for key in failure.record.allKeys() { serverRecord[key] = failure.record[key] }
                    pendingRecords[serverRecord.recordID] = serverRecord
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])
                } else {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
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
            logger.info("iCloud account signed in")
        case .signOut:
            logger.info("iCloud account signed out — sync paused")
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
