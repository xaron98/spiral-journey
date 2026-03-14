#if os(iOS)
import Foundation
import WatchConnectivity
import SpiralKit

/// Handles WatchConnectivity session on the iOS side.
/// Sends analysis snapshots to the Apple Watch and receives logged events.
@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityManager()
    var onEventReceived: ((CircadianEvent) -> Void)?
    var onEpisodeReceived: ((SleepEpisode) -> Void)?
    /// Called when Watch explicitly requests a fresh data push.
    var onDataRequested: (() -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Send full analysis context to Watch

    func sendAnalysis(records: [SleepRecord], events: [CircadianEvent], analysis: AnalysisResult,
                      language: String? = nil, appearance: String? = nil,
                      spiralType: String? = nil, period: Double? = nil,
                      startDate: Date? = nil,
                      contextBlocks: [ContextBlock]? = nil,
                      scheduleConflicts: [ScheduleConflict]? = nil) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }

        var context: [String: Any] = [:]

        if let data = try? JSONEncoder().encode(analysis) {
            context["analysisJSON"] = data
        }
        // Send slim records (no hourlyActivity/cosinor) to stay within the 65 KB context limit.
        // This allows sending far more days of history than the old 30-record cap.
        let slim = records.map { WatchSlimRecord(from: $0) }
        if let data = try? JSONEncoder().encode(slim) {
            context["recordsJSON"] = data
        }
        if let data = try? JSONEncoder().encode(events) {
            context["eventsJSON"] = data
        }
        if let language {
            context["language"] = language
        }
        if let appearance {
            context["appearance"] = appearance
        }
        if let spiralType {
            context["spiralType"] = spiralType
        }
        if let period {
            context["period"] = period
        }
        if let startDate {
            context["startDate"] = startDate.timeIntervalSince1970
        }
        // Context blocks and schedule conflicts (~1.5 KB typical)
        if let blocks = contextBlocks, !blocks.isEmpty,
           let data = try? JSONEncoder().encode(blocks) {
            context["contextBlocksJSON"] = data
        }
        if let conflicts = scheduleConflicts, !conflicts.isEmpty,
           let data = try? JSONEncoder().encode(conflicts) {
            context["conflictsJSON"] = data
        }

        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - Slim record type for Watch transfer

    /// Minimal representation of a SleepRecord for Watch transfer.
    /// Omits hourlyActivity and cosinor to keep payload within WatchConnectivity's 65 KB limit.
    struct WatchSlimRecord: Codable {
        var day: Int
        var date: Date
        var isWeekend: Bool
        var bedtimeHour: Double
        var wakeupHour: Double
        var sleepDuration: Double
        var phases: [PhaseInterval]
        var driftMinutes: Double

        init(from r: SleepRecord) {
            day = r.day; date = r.date; isWeekend = r.isWeekend
            bedtimeHour = r.bedtimeHour; wakeupHour = r.wakeupHour
            sleepDuration = r.sleepDuration; phases = r.phases
            driftMinutes = r.driftMinutes
        }

        func toSleepRecord() -> SleepRecord {
            SleepRecord(
                day: day, date: date, isWeekend: isWeekend,
                bedtimeHour: bedtimeHour, wakeupHour: wakeupHour,
                sleepDuration: sleepDuration, phases: phases,
                hourlyActivity: [], cosinor: .empty,
                driftMinutes: driftMinutes
            )
        }
    }

    // MARK: - Send events-only update to Watch

    /// Sends just the events list without re-encoding the full analysis payload.
    /// Call this after adding or removing an event on iPhone.
    /// Uses sendMessage for immediate delivery when Watch is reachable,
    /// falling back to updateApplicationContext for background delivery.
    func sendEvents(_ events: [CircadianEvent]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder().encode(events) else { return }
        // Always update the context so the Watch gets the events on next launch even if not reachable now.
        var context = WCSession.default.applicationContext
        context["eventsJSON"] = data
        try? WCSession.default.updateApplicationContext(context)
        // If Watch is active and reachable, push via sendMessage for instant delivery.
        // Use "eventsReplace" key so the Watch does an authoritative replace (not a merge),
        // which is required for deletions to take effect immediately.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["eventsReplace": data], replyHandler: nil)
        }
    }

    // MARK: - Send settings-only update to Watch

    /// Sends just settings (language, appearance, spiralType, period) without re-encoding full analysis data.
    /// Call this when the user changes a setting.
    func sendSettings(language: String, appearance: String,
                      spiralType: String? = nil, period: Double? = nil) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }
        // Merge into the existing application context so data keys are preserved.
        var context = WCSession.default.applicationContext
        context["language"]   = language
        context["appearance"] = appearance
        if let spiralType { context["spiralType"] = spiralType }
        if let period { context["period"] = period }
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    // Receive guaranteed-delivery payloads (sent via transferUserInfo when iPhone not reachable).
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    private nonisolated func handle(_ payload: [String: Any]) {
        if let data = payload["newEvent"] as? Data,
           let event = try? JSONDecoder().decode(CircadianEvent.self, from: data) {
            Task { @MainActor [weak self] in self?.onEventReceived?(event) }
        }
        if let data = payload["newEpisode"] as? Data,
           let episode = try? JSONDecoder().decode(SleepEpisode.self, from: data) {
            Task { @MainActor [weak self] in self?.onEpisodeReceived?(episode) }
        }
        // Watch is requesting a fresh data push (e.g. after reinstall or empty context)
        if payload["requestData"] != nil {
            Task { @MainActor [weak self] in self?.onDataRequested?() }
        }
    }
}
#endif
