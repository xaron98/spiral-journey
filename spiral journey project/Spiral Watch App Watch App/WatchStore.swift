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

    // Stored episodes (persisted locally — used for manual entries and standalone HK mode)
    private var episodes: [SleepEpisode] = []
    private var startDate: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    )

    /// True when records came from the iPhone (full historical data).
    /// When true, refreshFromHealthKit() delegates to requestDataFromPhone()
    /// rather than rebuilding records from the Watch's limited local HK data.
    private var hasIPhoneRecords = false

    /// True when there is no data at all (neither from iPhone nor locally logged).
    var isEmpty: Bool { records.isEmpty && episodes.isEmpty }

    /// The cursor position (absolute hours on the spiral timeline) as set by WatchSpiralView.
    var cursorAbsoluteHour: Double = 0

    /// Current wall-clock time expressed as absolute hours on the spiral timeline.
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
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        loadFromReceivedContext()
    }

    /// Reads receivedApplicationContext and applies it if non-empty.
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

    /// Refresh sleep data from the Watch's own HealthKit.
    ///
    /// Strategy:
    /// - If the iPhone is reachable, ask it for fresh data (it imports HK before replying).
    ///   This is the preferred path: iPhone has full history and latest HK data.
    /// - If the iPhone is NOT reachable, fetch the last 7 days from Watch HK directly
    ///   and rebuild records from those episodes. This standalone path only runs
    ///   when there is genuinely no iPhone connection.
    func refreshFromHealthKit() async {
        let hk = WatchHealthKitManager.shared
        guard hk.isAvailable else { return }

        if !hk.isAuthorized {
            await hk.requestAuthorization()
        }
        guard hk.isAuthorized else { return }

        // Preferred path: ask iPhone for fresh data (it imports HK before responding).
        if WatchConnectivityManager.shared.isReachable {
            print("[WatchHK] iPhone reachable — requesting fresh data from phone")
            WatchConnectivityManager.shared.requestDataFromPhone()
            return
        }

        // Standalone path: no iPhone connection.
        // Use startDate as epoch so coordinates are consistent with any cached records.
        let epoch = startDate
        print("[WatchHK] Standalone HK fetch with epoch=\(epoch)")

        let hkEpisodes = await hk.fetchRecentSleepEpisodes(days: 7, epoch: epoch, searchFromEpoch: false)
        print("[WatchHK] Fetched \(hkEpisodes.count) standalone episodes")
        guard !hkEpisodes.isEmpty else { return }

        mergeHealthKitEpisodes(hkEpisodes)
        // Rebuild records entirely from local episodes (standalone mode).
        let maxDay = episodes.map { Int($0.end / 24) + 1 }.max() ?? 7
        records = ManualDataConverter.convert(episodes: episodes, numDays: max(7, maxDay), startDate: epoch)
        analysis = ConclusionsEngine.generate(from: records)
        saveToDefaults()
        print("[WatchHK] Standalone done. records=\(records.count)")
    }

    /// Merge HealthKit-sourced episodes into the local list, replacing any existing
    /// episodes with the same HealthKit sample UUID to avoid duplicates on re-fetch.
    private func mergeHealthKitEpisodes(_ incoming: [SleepEpisode]) {
        // Remove stale HealthKit episodes and replace with the fresh batch.
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
        let maxDay = episodes.map { Int($0.end / 24) + 1 }.max() ?? 7
        let numDays = max(7, maxDay)
        records = ManualDataConverter.convert(episodes: episodes, numDays: numDays, startDate: startDate)
        analysis = ConclusionsEngine.generate(from: records)
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
                hasIPhoneRecords = !records.isEmpty
            } else if let full = try? JSONDecoder().decode([SleepRecord].self, from: data) {
                records = full
                hasIPhoneRecords = !records.isEmpty
            }
        }
        if let data = context["eventsReplace"] as? Data,
           let decoded = try? JSONDecoder().decode([CircadianEvent].self, from: data) {
            events = decoded.sorted { $0.absoluteHour < $1.absoluteHour }
        } else if let data = context["eventsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([CircadianEvent].self, from: data) {
            let knownIDs = Set(decoded.map { $0.id })
            let localOnly = events.filter { !knownIDs.contains($0.id) }
            events = (decoded + localOnly).sorted { $0.absoluteHour < $1.absoluteHour }
        }
        if let lang = context["language"] as? String { language = lang }
        if let app  = context["appearance"] as? String { appearance = app }
        if let st   = context["spiralType"] as? String, let decoded = SpiralType(rawValue: st) { spiralType = decoded }
        if let p    = context["period"] as? Double { period = p }
        if let d    = context["depthScale"] as? Double { depthScale = d }
        // Sync startDate from iPhone so absoluteHour values stay on the same timeline.
        if let ts = context["startDate"] as? Double {
            startDate = Date(timeIntervalSince1970: ts)
        }
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
        var hasIPhoneRecords: Bool?
        /// iPhone-sourced records persisted so the full spiral survives relaunch.
        var iPhoneRecords: Data?
    }

    private func saveToDefaults() {
        let iPhoneRecordsData: Data? = hasIPhoneRecords
            ? try? JSONEncoder().encode(records)
            : nil
        let stored = Stored(episodes: episodes, startDate: startDate,
                            language: language, appearance: appearance,
                            spiralType: spiralType, period: period,
                            events: events, hasIPhoneRecords: hasIPhoneRecords,
                            iPhoneRecords: iPhoneRecordsData)
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
        if let hir  = stored.hasIPhoneRecords { hasIPhoneRecords = hir }

        // Restore iPhone records — these are the historical source of truth.
        if hasIPhoneRecords,
           let recData = stored.iPhoneRecords,
           let decoded = try? JSONDecoder().decode([SleepRecord].self, from: recData) {
            records = decoded
            analysis = ConclusionsEngine.generate(from: records)
        } else if !episodes.isEmpty {
            recompute()
        }
    }

}
