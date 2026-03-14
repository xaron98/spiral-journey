import Foundation
import Observation
import SwiftUI
import SpiralKit

// MARK: - App Preferences

enum AppLanguage: String, Codable, CaseIterable {
    case en, es, ca, de, fr, zh, ja, ar

    var nativeName: String {
        switch self {
        case .en: return "English"
        case .es: return "Castellano"
        case .ca: return "Català"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .zh: return "中文"
        case .ja: return "日本語"
        case .ar: return "العربية"
        }
    }

    /// BCP 47 locale identifier used with Locale and xcstrings
    var localeIdentifier: String {
        switch self {
        case .zh: return "zh-Hans"
        default:  return rawValue
        }
    }

    /// Best match for the device's preferred languages. Falls back to .en.
    static var systemMatch: AppLanguage {
        for tag in Locale.preferredLanguages {
            let prefix = tag.lowercased()
            if prefix.hasPrefix("zh") { return .zh }
            if prefix.hasPrefix("ca") { return .ca }
            if prefix.hasPrefix("ar") { return .ar }
            for lang in AppLanguage.allCases {
                if prefix.hasPrefix(lang.rawValue) { return lang }
            }
        }
        return .en
    }
}

enum AppAppearance: String, Codable, CaseIterable {
    case dark, light, system

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }
}

/// Central state store for the app.
/// Holds sleep episodes, events, computed records, and analysis results.
@MainActor
@Observable
final class SpiralStore {

    // MARK: - Persisted State (UserDefaults)

    var sleepEpisodes: [SleepEpisode] = [] {
        didSet { save() }
    }
    var events: [CircadianEvent] = [] {
        didSet { save() }
    }
    var startDate: Date = Calendar.current.startOfDay(for: Date()) {
        didSet { save() }
    }
    var numDays: Int = 30 {
        didSet { save() }
    }
    var spiralType: SpiralType = .logarithmic {
        didSet {
            save()
            #if os(iOS)
            WatchConnectivityManager.shared.sendSettings(
                language: language.localeIdentifier,
                appearance: appearance.rawValue,
                spiralType: spiralType.rawValue,
                period: period
            )
            #endif
        }
    }
    var period: Double = 24.0 {
        didSet {
            save()
            #if os(iOS)
            WatchConnectivityManager.shared.sendSettings(
                language: language.localeIdentifier,
                appearance: appearance.rawValue,
                spiralType: spiralType.rawValue,
                period: period
            )
            #endif
        }
    }
    var linkGrowthToTau: Bool = false {
        didSet { save() }
    }
    var depthScale: Double = 1.5 {
        didSet { save() }
    }
    var showGrid: Bool = true {
        didSet { save() }
    }
    var language: AppLanguage = .systemMatch {
        didSet {
            save()
            #if os(iOS)
            WatchConnectivityManager.shared.sendSettings(
                language: language.localeIdentifier,
                appearance: appearance.rawValue
            )
            #endif
        }
    }
    var appearance: AppAppearance = .dark {
        didSet {
            save()
            #if os(iOS)
            WatchConnectivityManager.shared.sendSettings(
                language: language.localeIdentifier,
                appearance: appearance.rawValue
            )
            #endif
        }
    }

    // MARK: - Rephase State

    var rephasePlan: RephasePlan = RephasePlan() {
        didSet { save() }
    }
    var sleepGoal: SleepGoal = .generalHealthDefault {
        didSet { save() }
    }
    var hasCompletedOnboarding: Bool = false {
        didSet { save() }
    }
    var hasShownWelcome: Bool = false {
        didSet { save() }
    }
    var chronotypeResult: ChronotypeResult? = nil {
        didSet { save() }
    }
    var hasCompletedChronotype: Bool = false {
        didSet { save() }
    }
    var jetLagPlan: JetLagPlan? = nil {
        didSet { save() }
    }

    // MARK: - Computed State

    private(set) var records: [SleepRecord] = []
    private(set) var analysis: AnalysisResult = AnalysisResult()
    private(set) var isProcessing = false

    // MARK: - Init

    init() {
        // On the very first launch ever, start completely clean.
        // This ensures no leftover simulator/dev data appears to a real first-time user.
        #if targetEnvironment(simulator)
        // Simulator always starts completely fresh on every launch
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()
        #else
        let launchedKey = "spiral-journey-has-launched-v2"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            // Fresh install — wipe any leftover dev/beta data
            UserDefaults.standard.removeObject(forKey: "spiral-journey-store")
            UserDefaults.standard.set(true, forKey: launchedKey)
        }
        #endif
        load()
        // Only recompute if there are actual episodes — avoids generating
        // phantom records from empty data.
        if !sleepEpisodes.isEmpty {
            recompute()
        }
    }

    // MARK: - Data Processing

    /// Recompute SleepRecords and AnalysisResult from current episodes.
    func recompute() {
        guard !sleepEpisodes.isEmpty else {
            records = []
            analysis = AnalysisResult()
            return
        }
        isProcessing = true
        let eps = sleepEpisodes
        // Generate records only for days that overlap with at least one episode.
        // lastEndHour/period gives the fractional day of the last wakeup.
        // ceil gives us the first day index that has NO episode — that's our count.
        let lastEndHour = eps.map(\.end).max() ?? 0
        // Episodes are stored in absolute hours where 1 day = 24h always.
        // Divide by 24 (not by period/τ) to get the correct number of calendar days.
        let neededDays  = min(Int(ceil(lastEndHour / 24.0)), numDays)
        let n   = max(neededDays, 1)
        let sd  = startDate
        let evts = events
        let activeGoal = rephasePlan.isEnabled ? rephasePlan.asSleepGoal() : sleepGoal
        Task.detached(priority: .userInitiated) { [weak self] in
            let newRecords = ManualDataConverter.convert(episodes: eps, numDays: n, startDate: sd)
            let newAnalysis = ConclusionsEngine.generate(from: newRecords, goal: activeGoal)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.records = newRecords
                self.analysis = newAnalysis
                self.isProcessing = false
                // Sync to Apple Watch
                #if os(iOS)
                WatchConnectivityManager.shared.sendAnalysis(
                    records: newRecords,
                    events: evts,
                    analysis: newAnalysis,
                    language: self.language.localeIdentifier,
                    appearance: self.appearance.rawValue,
                    spiralType: self.spiralType.rawValue,
                    period: self.period,
                    startDate: sd
                )
                #endif
            }
        }
    }

    /// Merge HealthKit episodes into the store, deduplicating by healthKitSampleID.
    func mergeHealthKitEpisodes(_ newEpisodes: [SleepEpisode]) {
        let existingIDs = Set(sleepEpisodes.compactMap(\.healthKitSampleID))
        let toAdd = newEpisodes.filter { ep in
            guard let hkID = ep.healthKitSampleID else { return true }
            return !existingIDs.contains(hkID)
        }
        if !toAdd.isEmpty {
            sleepEpisodes.append(contentsOf: toAdd)
            sleepEpisodes.sort { $0.start < $1.start }
            recompute()
        }
    }

    func addEvent(_ event: CircadianEvent) {
        events.append(event)
        events.sort { $0.absoluteHour < $1.absoluteHour }
        #if os(iOS)
        WatchConnectivityManager.shared.sendEvents(events)
        #endif
    }

    func removeEpisode(id: UUID) {
        sleepEpisodes.removeAll { $0.id == id }
        recompute()
    }

    func removeEvent(id: UUID) {
        events.removeAll { $0.id == id }
        #if os(iOS)
        WatchConnectivityManager.shared.sendEvents(events)
        #endif
    }

    /// Wipe all user data and reset to factory defaults.
    func resetAllData() {
        UserDefaults.standard.removeObject(forKey: "spiral-journey-has-launched")
        UserDefaults.standard.removeObject(forKey: storageKey)
        sleepEpisodes = []
        events = []
        startDate = Calendar.current.startOfDay(for: Date())
        numDays = 30
        spiralType = .archimedean
        period = 24.0
        linkGrowthToTau = false
        depthScale = 1.5
        showGrid = true
        language = .en
        appearance = .dark
        rephasePlan = RephasePlan()
        hasCompletedOnboarding = false
        hasShownWelcome = false
        chronotypeResult = nil
        hasCompletedChronotype = false
        jetLagPlan = nil
        records = []
        analysis = AnalysisResult()
    }

    // MARK: - Persistence

    private let storageKey = "spiral-journey-store"

    /// Increment this when the onboarding flow changes significantly.
    /// Any stored version below this number will replay the welcome + tutorial.
    private let currentOnboardingVersion = 1

    private struct Stored: Codable {
        var sleepEpisodes: [SleepEpisode]
        var events: [CircadianEvent]
        var startDate: Date
        var numDays: Int
        var spiralType: SpiralType
        var period: Double
        var linkGrowthToTau: Bool
        var depthScale: Double?
        var showGrid: Bool?
        var language: AppLanguage?
        var appearance: AppAppearance?
        var rephasePlan: RephasePlan?
        var sleepGoal: SleepGoal?
        var hasCompletedOnboarding: Bool?
        var hasShownWelcome: Bool?
        var onboardingVersion: Int?
        var chronotypeResult: ChronotypeResult?
        var hasCompletedChronotype: Bool?
        var jetLagPlan: JetLagPlan?
    }

    private func save() {
        let stored = Stored(
            sleepEpisodes: sleepEpisodes,
            events: events,
            startDate: startDate,
            numDays: numDays,
            spiralType: spiralType,
            period: period,
            linkGrowthToTau: linkGrowthToTau,
            depthScale: depthScale,
            showGrid: showGrid,
            language: language,
            appearance: appearance,
            rephasePlan: rephasePlan,
            sleepGoal: sleepGoal,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasShownWelcome: hasShownWelcome,
            onboardingVersion: currentOnboardingVersion,
            chronotypeResult: chronotypeResult,
            hasCompletedChronotype: hasCompletedChronotype,
            jetLagPlan: jetLagPlan
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        sleepEpisodes = stored.sleepEpisodes
        events = stored.events
        startDate = stored.startDate
        numDays = stored.numDays
        spiralType = stored.spiralType
        period = stored.period
        linkGrowthToTau = stored.linkGrowthToTau
        if let ds   = stored.depthScale  { depthScale = ds }
        if let grid = stored.showGrid    { showGrid = grid }
        if let lang = stored.language    { language = lang }
        if let app  = stored.appearance  { appearance = app }
        if let rp   = stored.rephasePlan { rephasePlan = rp }
        if let sg   = stored.sleepGoal   { sleepGoal = sg }

        if let cr  = stored.chronotypeResult { chronotypeResult = cr }
        if let hcc = stored.hasCompletedChronotype { hasCompletedChronotype = hcc }
        if let jl  = stored.jetLagPlan { jetLagPlan = jl }

        // Only restore onboarding state if the stored version matches current.
        // If version is missing or outdated, the flags stay false → tutorial replays.
        let savedVersion = stored.onboardingVersion ?? 0
        if savedVersion >= currentOnboardingVersion {
            if let hco = stored.hasCompletedOnboarding { hasCompletedOnboarding = hco }
            if let hsw = stored.hasShownWelcome { hasShownWelcome = hsw }
        }
    }
}
