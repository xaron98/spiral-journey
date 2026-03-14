import Foundation
import Observation
import WatchConnectivity
import SpiralKit
import HealthKit

// MARK: - Slim record for WatchConnectivity transfer

/// Mirrors WatchConnectivityManager.WatchSlimRecord on the iOS side.
/// Decodes the compact payload sent from iPhone and reconstructs full SleepRecord objects.
struct WatchSlimRecord: Codable {
    var day: Int
    var date: Date
    var isWeekend: Bool
    var bedtimeHour: Double
    var wakeupHour: Double
    var sleepDuration: Double
    var phases: [PhaseInterval]
    var driftMinutes: Double

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

/// Lightweight observable store for the Watch app.
/// Starts empty. User logs sleep with the Digital Crown, or data arrives from iPhone.
@MainActor
@Observable
final class WatchStore {

    var records: [SleepRecord] = []
    var events: [CircadianEvent] = []
    var analysis: AnalysisResult = AnalysisResult()
    var contextBlocks: [ContextBlock] = []
    var scheduleConflicts: [ScheduleConflict] = []
    var isLoading = false

    /// Language synced from iPhone (BCP 47 locale identifier, e.g. "en", "es", "zh-Hans").
    var language: String = "en"
    /// Appearance synced from iPhone ("dark", "light", "system").
    var appearance: String = "dark"
    /// Spiral type synced from iPhone ("archimedean" or "logarithmic").
    var spiralType: SpiralType = .archimedean
    /// Circadian period synced from iPhone (hours, typically 24.0).
    var period: Double = 24.0
    /// Depth scale for perspective projection, synced from iPhone. Default 1.5.
    var depthScale: Double = 1.5

    // Stored episodes (persisted locally)
    private var episodes: [SleepEpisode] = []
    private var startDate: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    )

    /// True when there is no data at all (neither from iPhone nor locally logged).
    var isEmpty: Bool { records.isEmpty && episodes.isEmpty }

    /// The cursor position (absolute hours on the spiral timeline) as set by WatchSpiralView.
    /// WatchSpiralView writes this whenever the cursor moves or is initialised.
    /// WatchEventLogView reads it so events are placed at the cursor, not wall-clock time.
    var cursorAbsoluteHour: Double = 0

    /// Current wall-clock time expressed as absolute hours on the spiral timeline
    /// (hours elapsed since startDate midnight). Kept for fallback use.
    var currentAbsoluteHour: Double {
        let now = Date()
        let seconds = now.timeIntervalSince(startDate)
        return seconds / 3600.0
    }

    // Computed shortcuts
    var compositeScore: Int { analysis.composite }
    var sri: Double { analysis.stats.sri }
    var acrophase: Double { analysis.stats.meanAcrophase }
    var sleepDuration: Double { analysis.stats.meanSleepDuration }

    /// All records for the spiral view.
    var recentRecords: [SleepRecord] { records }

    // MARK: - Init

    init() {
        #if targetEnvironment(simulator)
        // Simulator: load sample sleep episodes so the spiral renders with colors
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()
        let simStart = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        startDate = simStart
        // 14 nights with slight natural variation in bedtime/wakeup
        let bedtimes:  [Double] = [23.0, 23.5, 0.0, 23.0, 23.5, 1.0, 0.5,
                                    22.5, 23.0, 23.5, 0.0, 23.0, 23.5, 0.0]
        let durations: [Double] = [7.5,  8.0,  7.0,  7.5,  8.0,  6.5, 7.0,
                                    8.5,  7.5,  8.0,  7.5,  7.0,  8.0, 7.5]
        for i in 0..<14 {
            let base = Double(i) * 24.0
            let bed = base + bedtimes[i]
            episodes.append(SleepEpisode(start: bed, end: bed + durations[i], source: .manual))
        }
        recompute()
        #else
        let launchedKey = "watchstore-has-launched-v2"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            UserDefaults.standard.set(true, forKey: launchedKey)
        } else {
            loadFromDefaults()
        }
        #endif
    }

    // MARK: - Data Loading

    /// Called from .task in ContentView.
    /// Reads any context that was already delivered by the iPhone before the app opened,
    /// then waits for live updates via WatchConnectivity.
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Note: WCSession.default.receivedApplicationContext may be empty here if the
        // session hasn't activated yet. The onSessionActivated callback in ContentView
        // will call loadFromReceivedContext() once activation completes.
        loadFromReceivedContext()
    }

    /// Reads receivedApplicationContext and applies it if non-empty.
    /// Safe to call multiple times — after activation, after receiving new context.
    func loadFromReceivedContext() {
        let received = WCSession.default.receivedApplicationContext
        if !received.isEmpty {
            updateFromContext(received)
        } else {
            if !episodes.isEmpty { recompute() }
            // Context empty — ask iPhone to push fresh data if reachable.
            WatchConnectivityManager.shared.requestDataFromPhone()
        }
    }

    // MARK: - HealthKit Sync

    /// Fetch recent sleep from HealthKit, merge into local episodes (dedup by HK UUID),
    /// recompute, and persist. Always runs regardless of whether iPhone data is present,
    /// so the Watch spiral stays current without needing to open the iPhone app.
    func refreshFromHealthKit() async {
        let hk = WatchHealthKitManager.shared
        guard hk.isAvailable else {
            print("[WatchHK] HK not available on this device")
            return
        }
        // Request authorization if not already granted (handles the case where
        // scenePhase .active fires before setupHealthKit() completes on relaunch).
        if !hk.isAuthorized {
            print("[WatchHK] Not authorized — requesting now")
            await hk.requestAuthorization()
        }
        guard hk.isAuthorized else {
            print("[WatchHK] Authorization denied — aborting")
            return
        }

        let calendar = Calendar.current

        // If the iPhone has synced a startDate that is older than 7 days, trust it.
        // Otherwise (standalone or iPhone epoch also recent) derive from HK data.
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let hasEstablishedEpoch = startDate < sevenDaysAgo

        print("[WatchHK] startDate=\(startDate), hasEstablishedEpoch=\(hasEstablishedEpoch)")

        // Always derive the epoch from HK data: find the earliest sleep sample in
        // the last 60 days and use midnight of that day as day-0.
        // This guarantees that ALL samples in the second fetch have absStart >= 0.
        let searchWindow = 60
        let tempEpoch = calendar.date(byAdding: .day, value: -searchWindow, to: Date()) ?? Date()
        let discoveryEpisodes = await hk.fetchRecentSleepEpisodes(days: searchWindow, epoch: tempEpoch, searchFromEpoch: true)
        print("[WatchHK] Discovery episodes found: \(discoveryEpisodes.count)")

        let epoch: Date
        if discoveryEpisodes.isEmpty {
            // No HK data at all — nothing to do.
            print("[WatchHK] No HK data found — aborting")
            return
        }

        if hasEstablishedEpoch {
            // iPhone epoch is older than 7 days — use it to keep coordinates consistent.
            epoch = startDate
        } else {
            // Derive epoch from the earliest HK sample.
            let earliestAbsHour = discoveryEpisodes.map(\.start).min() ?? 0
            let earliestDate = tempEpoch.addingTimeInterval(earliestAbsHour * 3600)
            epoch = calendar.startOfDay(for: earliestDate)
            startDate = epoch
            print("[WatchHK] Derived epoch from HK: \(epoch)")
        }

        // Re-fetch using the correct epoch so all absStart values are >= 0.
        // searchFromEpoch: true ensures we don't miss samples between epoch and (now-32d).
        let hkEpisodes = await hk.fetchRecentSleepEpisodes(days: searchWindow, epoch: epoch, searchFromEpoch: true)
        print("[WatchHK] Fetched \(hkEpisodes.count) episodes with epoch=\(epoch)")
        guard !hkEpisodes.isEmpty else {
            print("[WatchHK] No recent HK episodes — aborting")
            return
        }

        mergeHealthKitEpisodes(hkEpisodes)
        print("[WatchHK] After merge: \(episodes.count) total episodes")
        recompute()
        saveToDefaults()
        print("[WatchHK] Done. records=\(records.count)")
    }

    /// Merge HealthKit-sourced episodes into the local list, replacing any existing
    /// episodes with the same HealthKit sample UUID to avoid duplicates on re-fetch.
    private func mergeHealthKitEpisodes(_ incoming: [SleepEpisode]) {
        // Remove old HealthKit episodes that are covered by the new fetch.
        let incomingIDs = Set(incoming.compactMap(\.healthKitSampleID))
        episodes.removeAll { $0.source == .healthKit && $0.healthKitSampleID.map { incomingIDs.contains($0) } == true }

        // Also remove stale HealthKit episodes that were deleted from Health app
        // (keep only manual episodes + the fresh HK batch).
        episodes.removeAll { $0.source == .healthKit }
        episodes.append(contentsOf: incoming)
        episodes.sort { $0.start < $1.start }
    }

    // MARK: - Episode management

    /// Add a manually logged sleep episode, recompute, and persist.
    func addEpisode(_ episode: SleepEpisode) {
        episodes.append(episode)
        episodes.sort { $0.start < $1.start }

        // Recalculate startDate to cover all episodes
        if let firstStart = episodes.first?.start {
            // day 0 absolute hour corresponds to startDate
            // Keep existing startDate unless the episode starts before day 0
            if firstStart < 0 {
                startDate = Calendar.current.date(
                    byAdding: .hour, value: Int(firstStart), to: startDate) ?? startDate
            }
        }

        recompute()
        saveToDefaults()
        WatchConnectivityManager.shared.sendEpisode(episode)
    }

    private func recompute() {
        // Calculate enough days to cover all episodes, minimum 7
        let maxDay = episodes.map { Int($0.end / 24) + 1 }.max() ?? 7
        let numDays = max(7, maxDay)
        let newRecords = ManualDataConverter.convert(episodes: episodes, numDays: numDays, startDate: startDate)
        let newAnalysis = ConclusionsEngine.generate(from: newRecords)
        records = newRecords
        analysis = newAnalysis
    }

    // MARK: - WatchConnectivity

    /// Called by WatchConnectivityManager when new context arrives from iPhone.
    func updateFromContext(_ context: [String: Any]) {
        if let data = context["analysisJSON"] as? Data,
           let decoded = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            analysis = decoded
        }
        if let data = context["recordsJSON"] as? Data {
            // Try slim format first (new), fall back to full SleepRecord (legacy)
            if let slim = try? JSONDecoder().decode([WatchSlimRecord].self, from: data) {
                records = slim.map { $0.toSleepRecord() }
            } else if let full = try? JSONDecoder().decode([SleepRecord].self, from: data) {
                records = full
            }
        }
        if let data = context["eventsReplace"] as? Data,
           let decoded = try? JSONDecoder().decode([CircadianEvent].self, from: data) {
            // Authoritative replace from iPhone (add or delete) — use the list as-is.
            events = decoded.sorted { $0.absoluteHour < $1.absoluteHour }
        } else if let data = context["eventsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([CircadianEvent].self, from: data) {
            // Background context (applicationContext on startup) — merge to keep any
            // locally-logged events not yet echoed back from iPhone.
            let knownIDs = Set(decoded.map { $0.id })
            let localOnly = events.filter { !knownIDs.contains($0.id) }
            events = (decoded + localOnly).sorted { $0.absoluteHour < $1.absoluteHour }
        }
        if let lang = context["language"] as? String {
            language = lang
        }
        if let app = context["appearance"] as? String {
            appearance = app
        }
        if let st = context["spiralType"] as? String, let decoded = SpiralType(rawValue: st) {
            spiralType = decoded
        }
        if let p = context["period"] as? Double {
            period = p
        }
        if let d = context["depthScale"] as? Double {
            depthScale = d
        }
        // Sync startDate from iPhone so absoluteHour values in events and records
        // are interpreted on the same timeline reference on both devices.
        if let ts = context["startDate"] as? Double {
            startDate = Date(timeIntervalSince1970: ts)
        }
        // Context blocks and schedule conflicts
        if let data = context["contextBlocksJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([ContextBlock].self, from: data) {
            contextBlocks = decoded
        }
        if let data = context["conflictsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([ScheduleConflict].self, from: data) {
            scheduleConflicts = decoded
        }
        saveToDefaults()
    }

    /// Append an event logged on the watch and send it to the iPhone.
    func logEvent(_ event: CircadianEvent) {
        events.append(event)
        saveToDefaults()
        WatchConnectivityManager.shared.sendEvent(event)
    }

    // MARK: - Persistence

    private let defaultsKey = "watchstore-episodes-v2"

    private struct Stored: Codable {
        var episodes: [SleepEpisode]
        var startDate: Date
        var language: String?
        var appearance: String?
        var spiralType: SpiralType?
        var period: Double?
        var events: [CircadianEvent]?
    }

    private func saveToDefaults() {
        let stored = Stored(episodes: episodes, startDate: startDate,
                            language: language, appearance: appearance,
                            spiralType: spiralType, period: period,
                            events: events)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        episodes = stored.episodes
        startDate = stored.startDate
        if let lang = stored.language { language = lang }
        if let app  = stored.appearance { appearance = app }
        if let st   = stored.spiralType { spiralType = st }
        if let p    = stored.period { period = p }
        if let evs  = stored.events { events = evs }
        if !episodes.isEmpty { recompute() }
    }

}
