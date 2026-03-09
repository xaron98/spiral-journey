import Foundation
import Observation
import HealthKit
import SpiralKit

/// Lightweight observable store for the Watch app.
/// Starts empty. User logs sleep with the Digital Crown, or data arrives from iPhone.
@MainActor
@Observable
final class WatchStore {

    var records: [SleepRecord] = []
    var events: [CircadianEvent] = []
    var analysis: AnalysisResult = AnalysisResult()
    var isLoading = false

    /// Language synced from iPhone (BCP 47 locale identifier, e.g. "en", "es", "zh-Hans").
    var language: String = "en"
    /// Appearance synced from iPhone ("dark", "light", "system").
    var appearance: String = "dark"

    // Stored episodes (persisted locally)
    private var episodes: [SleepEpisode] = []
    private var startDate: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    )

    /// True when no episodes have been logged yet.
    var isEmpty: Bool { episodes.isEmpty }

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
        // Simulator always starts completely fresh on every launch
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()
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

    /// Called from .task in ContentView. Tries HealthKit on device; simulator starts empty.
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // If we already have locally-stored episodes, use them
        if !episodes.isEmpty {
            recompute()
            return
        }

        #if targetEnvironment(simulator)
        // Start completely empty — let the user log via Crown
        return
        #else
        let hkEpisodes = await fetchHealthKitEpisodes(days: 14)
        if !hkEpisodes.isEmpty {
            startDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            episodes = hkEpisodes
            recompute()
        }
        // No fallback to sample data — start empty if HealthKit has nothing
        #endif
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
        if let data = context["recordsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([SleepRecord].self, from: data) {
            records = decoded
        }
        if let data = context["eventsJSON"] as? Data,
           let decoded = try? JSONDecoder().decode([CircadianEvent].self, from: data) {
            events = decoded
        }
        if let lang = context["language"] as? String {
            language = lang
            saveToDefaults()
        }
        if let app = context["appearance"] as? String {
            appearance = app
            saveToDefaults()
        }
    }

    /// Append an event logged on the watch and send it to the iPhone.
    func logEvent(_ event: CircadianEvent) {
        events.append(event)
        WatchConnectivityManager.shared.sendEvent(event)
    }

    // MARK: - Persistence

    private let defaultsKey = "watchstore-episodes-v2"

    private struct Stored: Codable {
        var episodes: [SleepEpisode]
        var startDate: Date
        var language: String?
        var appearance: String?
    }

    private func saveToDefaults() {
        let stored = Stored(episodes: episodes, startDate: startDate,
                            language: language, appearance: appearance)
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
        if !episodes.isEmpty { recompute() }
    }

    // MARK: - HealthKit

    private func fetchHealthKitEpisodes(days: Int) async -> [SleepEpisode] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let hkStore = HKHealthStore()
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        do {
            try await hkStore.requestAuthorization(toShare: [], read: [sleepType])
        } catch {
            return []
        }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let sleepOnly = samples.filter {
                    HKCategoryValueSleepAnalysis(rawValue: $0.value) != .inBed
                }
                var eps: [SleepEpisode] = []
                for s in sleepOnly.sorted(by: { $0.startDate < $1.startDate }) {
                    let absStart = s.startDate.timeIntervalSince(start) / 3600
                    let absEnd   = s.endDate.timeIntervalSince(start) / 3600
                    guard absEnd > absStart else { continue }
                    if let last = eps.last, absStart - last.end < 0.5 {
                        eps[eps.count - 1] = SleepEpisode(
                            id: last.id, start: last.start,
                            end: max(last.end, absEnd),
                            source: .healthKit,
                            healthKitSampleID: last.healthKitSampleID
                        )
                    } else {
                        eps.append(SleepEpisode(
                            start: absStart, end: absEnd,
                            source: .healthKit,
                            healthKitSampleID: s.uuid.uuidString
                        ))
                    }
                }
                continuation.resume(returning: eps)
            }
            hkStore.execute(query)
        }
    }
}
