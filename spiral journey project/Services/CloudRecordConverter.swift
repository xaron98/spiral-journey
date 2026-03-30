import CloudKit
import SpiralKit

// MARK: - CloudSettings

/// Sendable intermediate type for passing settings between CloudSyncManager and SpiralStore.
/// Avoids CloudSyncManager needing to reference @MainActor SpiralStore types directly.
struct CloudSettings: Sendable {
    var startDate: Date
    var numDays: Int
    var spiralType: String        // SpiralType.rawValue
    var period: Double
    var linkGrowthToTau: Bool
    var depthScale: Double
    var showGrid: Bool
    var language: String          // AppLanguage.rawValue
    var appearance: String        // AppAppearance.rawValue
    var rephasePlanData: Data?    // JSON-encoded RephasePlan
    var sleepGoalData: Data?      // JSON-encoded SleepGoal
    var modifiedAt: Date
}

// MARK: - CloudRecordConverter

/// Pure CKRecord ↔ Swift model conversion functions.
/// No side effects, no dependencies on SpiralStore or UI.
enum CloudRecordConverter {

    // MARK: - Zone

    static let zoneName = "SpiralData"
    static let zoneID = CKRecordZone.ID(
        zoneName: zoneName,
        ownerName: CKCurrentUserDefaultName
    )

    // MARK: - Record Type Names

    static let episodeType  = "SleepEpisode"
    static let eventType    = "CircadianEvent"
    static let settingsType = "Settings"
    static let settingsRecordName = "user-settings"

    // MARK: - SleepEpisode ↔ CKRecord

    static func record(from episode: SleepEpisode, modifiedAt: Date = Date()) -> CKRecord {
        let recordID = CKRecord.ID(recordName: episode.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: episodeType, recordID: recordID)
        record["episodeID"]          = episode.id.uuidString as CKRecordValue
        record["start"]              = episode.start as CKRecordValue
        record["end"]                = episode.end as CKRecordValue
        record["source"]             = episode.source.rawValue as CKRecordValue
        record["healthKitSampleID"]  = episode.healthKitSampleID as CKRecordValue?
        record["phase"]              = episode.phase?.rawValue as CKRecordValue?
        record["modifiedAt"]         = modifiedAt as CKRecordValue
        return record
    }

    static func episode(from record: CKRecord) -> SleepEpisode? {
        guard record.recordType == episodeType,
              let idStr   = record["episodeID"] as? String,
              let id      = UUID(uuidString: idStr),
              let start   = record["start"] as? Double,
              let end     = record["end"] as? Double,
              let srcStr  = record["source"] as? String,
              let source  = DataSource(rawValue: srcStr)
        else { return nil }

        let hkID  = record["healthKitSampleID"] as? String
        let phase = (record["phase"] as? String).flatMap { SleepPhase(rawValue: $0) }

        return SleepEpisode(id: id, start: start, end: end,
                            source: source, healthKitSampleID: hkID, phase: phase)
    }

    // MARK: - CircadianEvent ↔ CKRecord

    static func record(from event: CircadianEvent, modifiedAt: Date = Date()) -> CKRecord {
        let recordID = CKRecord.ID(recordName: event.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: eventType, recordID: recordID)
        record["eventID"]      = event.id.uuidString as CKRecordValue
        record["eventType"]    = event.type.rawValue as CKRecordValue
        record["absoluteHour"] = event.absoluteHour as CKRecordValue
        record["timestamp"]    = event.timestamp as CKRecordValue
        record["note"]         = event.note as CKRecordValue?
        if let dur = event.durationHours {
            record["durationHours"] = dur as CKRecordValue
        }
        record["modifiedAt"]   = modifiedAt as CKRecordValue
        return record
    }

    static func event(from record: CKRecord) -> CircadianEvent? {
        guard record.recordType == eventType,
              let idStr      = record["eventID"] as? String,
              let id         = UUID(uuidString: idStr),
              let typeStr    = record["eventType"] as? String,
              let type       = EventType(rawValue: typeStr),
              let absHour    = record["absoluteHour"] as? Double,
              let timestamp  = record["timestamp"] as? Date
        else { return nil }

        return CircadianEvent(id: id, type: type, absoluteHour: absHour,
                              timestamp: timestamp, note: record["note"] as? String,
                              durationHours: record["durationHours"] as? Double)
    }

    // MARK: - CloudSettings ↔ CKRecord

    static func settingsRecord(from settings: CloudSettings) -> CKRecord {
        let recordID = CKRecord.ID(recordName: settingsRecordName, zoneID: zoneID)
        let record = CKRecord(recordType: settingsType, recordID: recordID)
        record["startDate"]       = settings.startDate as CKRecordValue
        record["numDays"]         = Int64(settings.numDays) as CKRecordValue
        record["spiralType"]      = settings.spiralType as CKRecordValue
        record["period"]          = settings.period as CKRecordValue
        record["linkGrowthToTau"] = Int64(settings.linkGrowthToTau ? 1 : 0) as CKRecordValue
        record["depthScale"]      = settings.depthScale as CKRecordValue
        record["showGrid"]        = Int64(settings.showGrid ? 1 : 0) as CKRecordValue
        record["language"]        = settings.language as CKRecordValue
        record["appearance"]      = settings.appearance as CKRecordValue
        record["rephasePlan"]     = settings.rephasePlanData as CKRecordValue?
        record["sleepGoal"]       = settings.sleepGoalData as CKRecordValue?
        record["modifiedAt"]      = settings.modifiedAt as CKRecordValue
        return record
    }

    static func settings(from record: CKRecord) -> CloudSettings? {
        guard record.recordType == settingsType,
              let startDate  = record["startDate"] as? Date,
              let numDaysRaw = record["numDays"] as? Int64,
              let spiralType = record["spiralType"] as? String,
              let period     = record["period"] as? Double,
              let language   = record["language"] as? String,
              let appearance = record["appearance"] as? String,
              let modifiedAt = record["modifiedAt"] as? Date
        else { return nil }

        let linkGrowthToTau = (record["linkGrowthToTau"] as? Int64 ?? 0) != 0
        let showGrid        = (record["showGrid"] as? Int64 ?? 0) != 0
        let depthScale      = record["depthScale"] as? Double ?? 0.15

        return CloudSettings(
            startDate: startDate,
            numDays: Int(numDaysRaw),
            spiralType: spiralType,
            period: period,
            linkGrowthToTau: linkGrowthToTau,
            depthScale: depthScale,
            showGrid: showGrid,
            language: language,
            appearance: appearance,
            rephasePlanData: record["rephasePlan"] as? Data,
            sleepGoalData: record["sleepGoal"] as? Data,
            modifiedAt: modifiedAt
        )
    }

    // MARK: - Record ID helpers

    static func episodeRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    static func eventRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    static var settingsRecordID: CKRecord.ID {
        CKRecord.ID(recordName: settingsRecordName, zoneID: zoneID)
    }
}
