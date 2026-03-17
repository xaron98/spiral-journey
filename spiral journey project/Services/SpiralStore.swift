import Foundation
import Observation
import SwiftUI
import SpiralKit
import WidgetKit

// MARK: - App Preferences

enum AppLanguage: String, Codable, CaseIterable {
    case system, en, es, ca, de, fr, zh, ja, ar

    var nativeName: String {
        switch self {
        case .system: return "System"
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

    /// BCP 47 locale identifier used with Locale and xcstrings.
    /// For `.system`, resolves dynamically from iOS preferred languages.
    var localeIdentifier: String {
        switch self {
        case .system: return AppLanguage.resolvedSystemLocale
        case .zh:     return "zh-Hans"
        default:      return rawValue
        }
    }

    /// Resolves the best matching locale identifier from iOS preferred languages.
    static var resolvedSystemLocale: String {
        for tag in Locale.preferredLanguages {
            let prefix = tag.lowercased()
            if prefix.hasPrefix("zh") { return "zh-Hans" }
            if prefix.hasPrefix("ca") { return "ca" }
            if prefix.hasPrefix("ar") { return "ar" }
            for lang in AppLanguage.allCases where lang != .system {
                if prefix.hasPrefix(lang.rawValue) { return lang.rawValue }
            }
        }
        return "en"
    }

    /// Best match for the device's preferred languages. Falls back to .en.
    static var systemMatch: AppLanguage { .system }
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
    var depthScale: Double = 0.6 {
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
    var notificationsEnabled: Bool = false {
        didSet {
            save()
            Task { await updateWeeklyDigest() }
        }
    }

    // MARK: - Prediction

    var predictionEnabled: Bool = false {
        didSet { save() }
    }
    var predictionOverlayEnabled: Bool = false {
        didSet { save() }
    }
    /// Use Core ML model instead of heuristic when available.
    var mlPredictionEnabled: Bool = true {
        didSet { save() }
    }
    private(set) var latestPrediction: PredictionOutput? = nil
    private(set) var predictionHistory: [PredictionResult] = []
    /// Whether historical predictions have been retroactively bootstrapped from existing records.
    var hasBootstrappedPredictions: Bool = false {
        didSet { save() }
    }

    // MARK: - Model Training State

    /// Last date the ML model was retrained on-device (nil = never).
    var lastModelTrainedDate: Date? = nil {
        didSet { save() }
    }
    /// Number of samples used in the last training run.
    var modelTrainingSampleCount: Int = 0 {
        didSet { save() }
    }

    // MARK: - Context Blocks

    var contextBlocks: [ContextBlock] = [] {
        didSet { save(); recomputeConflicts() }
    }
    var contextBlocksEnabled: Bool = false {
        didSet { save() }
    }
    var contextBufferMinutes: Double = 60.0 {
        didSet { save(); recomputeConflicts() }
    }
    /// Rolling history of daily conflict snapshots for trend analysis.
    /// Capped at 90 days. Updated each time conflicts are recomputed.
    private(set) var conflictHistory: [ConflictSnapshot] = []
    /// Computed conflict trend (current vs previous week).
    var conflictTrend: ConflictTrendEngine.ConflictTrend? {
        ConflictTrendEngine.analyze(snapshots: conflictHistory)
    }

    // MARK: - Enhanced Coach State

    /// Streak tracking (consecutive nights within goal).
    private(set) var streakHistory: StreakData = StreakData() {
        didSet { save() }
    }
    /// Stats from the previous week for week-over-week comparison.
    private(set) var previousWeekStats: SleepStats? = nil {
        didSet { save() }
    }
    /// Previous composite score for celebration detection.
    private(set) var previousCompositeScore: Int? = nil {
        didSet { save() }
    }
    /// Tracks which micro-habit IDs the user has marked as completed.
    var microHabitCompletions: [String: Bool] = [:] {
        didSet { save() }
    }

    /// Toggle a micro-habit completion. Key is "issueKey.cycleDay".
    func toggleMicroHabit(_ habit: MicroHabit) {
        let key = "\(habit.issueKey.rawValue).\(habit.cycleDay)"
        microHabitCompletions[key] = !(microHabitCompletions[key] ?? false)
    }

    /// Check if a micro-habit is completed.
    func isMicroHabitCompleted(_ habit: MicroHabit) -> Bool {
        let key = "\(habit.issueKey.rawValue).\(habit.cycleDay)"
        return microHabitCompletions[key] ?? false
    }

    // MARK: - LLM Chat State

    /// Whether the user has enabled the AI coach chat feature.
    var llmEnabled: Bool = false {
        didSet { save() }
    }
    /// Persisted chat message history.
    var chatHistory: [ChatMessage] = [] {
        didSet { saveLocalOnly() }
    }

    // MARK: - CloudKit Sync

    /// Set by the app entry point after CloudSyncManager is initialized.
    var cloudSync: CloudSyncManager?

    /// True while applying remote CloudKit changes — prevents save() from re-pushing to CloudKit.
    private var isSyncingFromCloud = false
    /// True during init load — prevents didSet from triggering save() on every property.
    private var isLoading = false

    // MARK: - Computed State

    private(set) var records: [SleepRecord] = []
    private(set) var analysis: AnalysisResult = AnalysisResult()
    private(set) var isProcessing = false
    private(set) var hrvData: [NightlyHRV] = []
    private(set) var scheduleConflicts: [ScheduleConflict] = []

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
        UserDefaults(suiteName: Self.appGroupID)?.removeObject(forKey: "spiral-journey-store")
        #else
        let launchedKey = "spiral-journey-has-launched-v2"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            // Fresh install — wipe any leftover dev/beta data
            UserDefaults.standard.removeObject(forKey: "spiral-journey-store")
            UserDefaults(suiteName: Self.appGroupID)?.removeObject(forKey: "spiral-journey-store")
            UserDefaults.standard.set(true, forKey: launchedKey)
        }
        #endif
        load()

        #if targetEnvironment(simulator)
        // Inject realistic mock data for App Store screenshots
        if sleepEpisodes.isEmpty {
            let mock = MockDataGenerator.generate()
            startDate = mock.startDate
            numDays = 8
            sleepEpisodes = mock.episodes
            events = mock.events
            hasCompletedOnboarding = true
            hasShownWelcome = true
            hasCompletedChronotype = true
            predictionEnabled = true
        }
        #endif

        // If HealthKit episodes are present, ensure startDate and numDays are
        // consistent with the actual data.
        reconcileEpochWithEpisodes()
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
        let blocks = contextBlocks
        let blocksEnabled = contextBlocksEnabled
        let bufferMins = contextBufferMinutes
        let prevStats = previousWeekStats
        let prevComposite = previousCompositeScore
        let currentStreak = streakHistory
        let currentEvents = events
        Task.detached(priority: .userInitiated) { [weak self] in
            let newRecords = ManualDataConverter.convert(episodes: eps, numDays: n, startDate: sd)
            // Use context-aware analysis if blocks are enabled
            let newAnalysis: AnalysisResult
            let newConflicts: [ScheduleConflict]
            if blocksEnabled && !blocks.isEmpty {
                let conflicts = ScheduleConflictDetector.detect(
                    records: newRecords, blocks: blocks, bufferMinutes: bufferMins
                )
                newConflicts = conflicts
                newAnalysis = ConclusionsEngine.generate(
                    from: newRecords, goal: activeGoal,
                    events: currentEvents,
                    previousStats: prevStats,
                    previousCompositeScore: prevComposite,
                    streakHistory: currentStreak,
                    contextBlocks: blocks, conflicts: conflicts
                )
            } else {
                newConflicts = []
                newAnalysis = ConclusionsEngine.generate(
                    from: newRecords, goal: activeGoal,
                    events: currentEvents,
                    previousStats: prevStats,
                    previousCompositeScore: prevComposite,
                    streakHistory: currentStreak
                )
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.records = newRecords
                self.analysis = newAnalysis
                self.scheduleConflicts = newConflicts
                // Update enhanced coach state
                if let enhanced = newAnalysis.enhancedCoach {
                    self.streakHistory = enhanced.streak
                }
                // Save previous stats/score for next week-over-week comparison
                self.previousWeekStats = newAnalysis.stats
                self.previousCompositeScore = newAnalysis.composite
                // Append daily conflict snapshot for trend tracking
                if !newConflicts.isEmpty {
                    let snapshot = ConflictSnapshot.from(conflicts: newConflicts)
                    self.conflictHistory.append(snapshot)
                    self.conflictHistory = ConflictTrendEngine.trimmed(self.conflictHistory, maxDays: 90)
                }
                self.isProcessing = false
                // Auto-enable prediction for existing users with enough data
                if !self.predictionEnabled && self.records.count >= 4 {
                    self.predictionEnabled = true
                }
                // Bootstrap ground truth from historical records (one-time)
                PredictionService.bootstrapHistoricalPredictions(store: self)
                // Evaluate past predictions against actual sleep data (ground truth)
                PredictionService.evaluatePastPredictions(store: self)
                // Retrain ML model if enough ground truth has accumulated
                ModelTrainingService.retrainIfNeeded(store: self)
                // Update sleep prediction (no-op if flag is off)
                PredictionService.generatePrediction(
                    store: self,
                    goalDuration: activeGoal.targetDuration
                )
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
                    startDate: sd,
                    contextBlocks: self.contextBlocksEnabled ? self.contextBlocks : nil,
                    scheduleConflicts: newConflicts.isEmpty ? nil : newConflicts
                )
                #endif
            }
        }
    }

    /// Merge HealthKit episodes into the store, deduplicating by healthKitSampleID.
    /// Ensure startDate and numDays are consistent with the stored episodes.
    /// Called once after load() to fix any mismatch that arose from an incorrect epoch
    /// at import time (e.g. install date used as epoch instead of first-sleep date).
    ///
    /// HealthKit episodes carry absolute hours relative to the stored startDate.
    /// If startDate is wrong (too late), early episodes may have absStart < 0 and were
    /// never stored. This method can only fix what IS stored. The real fix for missing
    /// early episodes happens in importAndAdjustEpoch → applyHealthKitResult on next launch.
    ///
    /// What this CAN fix: if episodes are present and startDate is set to install date
    /// (today or very recent) but episodes have absStart that implies they started on
    /// an earlier real date — but wait, absStart is always relative to startDate so we
    /// cannot infer the wall-clock date from absStart alone without knowing startDate.
    ///
    /// Instead this method just ensures numDays always covers today.
    private func reconcileEpochWithEpisodes() {
        guard !sleepEpisodes.isEmpty else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysToToday = calendar.dateComponents([.day], from: startDate, to: today).day ?? 0
        let needed = daysToToday + 1
        if needed > numDays {
            numDays = needed
        }
    }

    /// Apply the result of importAndAdjustEpoch.
    ///
    /// The incoming `episodes` are already expressed in absolute hours relative to `epoch`,
    /// so the correct approach is to:
    ///  1. Replace ALL stored HealthKit episodes with the freshly-fetched ones (which have
    ///     correct coordinates relative to the correct epoch). Manual episodes are preserved.
    ///  2. Update startDate to the new epoch (which may be earlier than the stored one).
    ///  3. Ensure numDays covers from the new startDate through today.
    ///
    /// Replacing rather than merging fixes the case where a previous import used the
    /// wrong epoch (e.g. install date) and stored episodes with shifted coordinates.
    func applyHealthKitResult(epoch: Date, episodes: [SleepEpisode]) {
        let calendar = Calendar.current
        print("[Store] applyHealthKitResult: epoch=\(epoch), currentStartDate=\(startDate), episodes=\(episodes.count)")

        // Keep manually-entered episodes — replace all HealthKit ones with the fresh fetch.
        let manualEpisodes = sleepEpisodes.filter { $0.source == .manual }
        let combined = (manualEpisodes + episodes).sorted { $0.start < $1.start }

        // Update startDate before writing episodes so save() persists the correct epoch.
        let newEpoch = min(epoch, startDate)
        print("[Store] newEpoch=\(newEpoch), will update startDate: \(newEpoch < startDate)")
        if newEpoch < startDate {
            startDate = newEpoch
            print("[Store] startDate updated to \(startDate)")
        }

        // Ensure numDays covers from startDate through today.
        let today = calendar.startOfDay(for: Date())
        let daysToToday = calendar.dateComponents([.day], from: startDate, to: today).day ?? 0
        if daysToToday + 1 > numDays {
            numDays = daysToToday + 1
        }

        // Write the combined episode list and recompute.
        // Suppress CloudKit push for episodes that already exist remotely —
        // only push genuinely new ones (those not previously in the store).
        let existingHKIDs = Set(sleepEpisodes.compactMap(\.healthKitSampleID))
        sleepEpisodes = combined
        recompute()
        let newOnes = episodes.filter { ep in
            guard let hkID = ep.healthKitSampleID else { return true }
            return !existingHKIDs.contains(hkID)
        }
        for ep in newOnes { cloudSync?.enqueueEpisodeSave(ep) }
    }

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
            // Push new episodes to CloudKit
            for ep in toAdd { cloudSync?.enqueueEpisodeSave(ep) }
        }
    }

    func addEvent(_ event: CircadianEvent) {
        events.append(event)
        events.sort { $0.absoluteHour < $1.absoluteHour }
        #if os(iOS)
        WatchConnectivityManager.shared.sendEvents(events)
        #endif
        cloudSync?.enqueueEventSave(event)
    }

    /// Refresh nightly HRV data from HealthKit.
    func refreshHRV() async {
        #if !targetEnvironment(simulator)
        hrvData = await HealthKitManager.shared.fetchNightlyHRV(days: numDays)
        #endif
    }

    func removeEpisode(id: UUID) {
        sleepEpisodes.removeAll { $0.id == id }
        recompute()
        cloudSync?.enqueueEpisodeDelete(id: id)
    }

    func removeEvent(id: UUID) {
        events.removeAll { $0.id == id }
        #if os(iOS)
        WatchConnectivityManager.shared.sendEvents(events)
        #endif
        cloudSync?.enqueueEventDelete(id: id)
    }

    // MARK: - Prediction Updates

    /// Store a new prediction result and update the latest prediction.
    func updatePrediction(_ result: PredictionResult) {
        latestPrediction = result.prediction
        predictionHistory.append(result)
        // Keep last 90 predictions
        if predictionHistory.count > 90 {
            predictionHistory = Array(predictionHistory.suffix(90))
        }
        save()
    }

    /// Append retroactively bootstrapped predictions (already evaluated).
    func appendBootstrappedPredictions(_ results: [PredictionResult]) {
        predictionHistory.append(contentsOf: results)
        // Keep last 90
        if predictionHistory.count > 90 {
            predictionHistory = Array(predictionHistory.suffix(90))
        }
        save()
    }

    /// Evaluate unevaluated predictions against actual sleep records (ground truth).
    ///
    /// For each prediction in history that has no `actual` data yet, check if
    /// a SleepRecord exists for the prediction's target date. If so, fill in
    /// the actual bedtime/wake/duration and compute error metrics.
    /// This accumulates the training dataset for future Core ML personalisation.
    func evaluateUnevaluatedPredictions() {
        let calendar = Calendar.current
        var updated = false

        for i in predictionHistory.indices {
            guard predictionHistory[i].actual == nil else { continue }

            let targetDate = predictionHistory[i].prediction.targetDate
            // Only evaluate predictions ≥ 12 h old so actual data has time to arrive
            guard Date().timeIntervalSince(targetDate) > 12 * 3600 else { continue }

            if let record = records.first(where: {
                calendar.isDate($0.date, inSameDayAs: targetDate)
            }) {
                predictionHistory[i].evaluate(
                    bedtime: record.bedtimeHour,
                    wake: record.wakeupHour,
                    duration: record.sleepDuration
                )
                updated = true
            }
        }

        if updated { save() }
    }

    // MARK: - Context Block CRUD

    func addContextBlock(_ block: ContextBlock) {
        contextBlocks.append(block)
    }

    func removeContextBlock(id: UUID) {
        contextBlocks.removeAll { $0.id == id }
    }

    func updateContextBlock(_ block: ContextBlock) {
        if let idx = contextBlocks.firstIndex(where: { $0.id == block.id }) {
            contextBlocks[idx] = block
        }
    }

    /// Recompute schedule conflicts from current records and context blocks.
    /// Called after records change (via recompute) or blocks change.
    /// Also appends a daily snapshot to `conflictHistory` for trend tracking.
    func recomputeConflicts() {
        guard contextBlocksEnabled, !contextBlocks.isEmpty, !records.isEmpty else {
            scheduleConflicts = []
            return
        }
        let conflicts = ScheduleConflictDetector.detect(
            records: records,
            blocks: contextBlocks,
            bufferMinutes: contextBufferMinutes
        )
        scheduleConflicts = conflicts

        // Append daily snapshot for trend tracking (deduplicated by date in trimmed())
        let snapshot = ConflictSnapshot.from(conflicts: conflicts)
        conflictHistory.append(snapshot)
        conflictHistory = ConflictTrendEngine.trimmed(conflictHistory, maxDays: 90)
        save()
    }

    /// Wipe all user data and reset to factory defaults.
    func resetAllData() {
        // Clear both v1 and v2 launch keys + CloudKit timestamp
        UserDefaults.standard.removeObject(forKey: "spiral-journey-has-launched")
        UserDefaults.standard.removeObject(forKey: "spiral-journey-has-launched-v2")
        UserDefaults.standard.removeObject(forKey: "spiral-journey-settings-modified-at")
        UserDefaults.standard.removeObject(forKey: storageKey)
        sharedDefaults.removeObject(forKey: storageKey)
        sleepEpisodes = []
        events = []
        startDate = Calendar.current.startOfDay(for: Date())
        numDays = 30
        spiralType = .logarithmic          // match property default (was .archimedean — wrong)
        period = 24.0
        linkGrowthToTau = false
        depthScale = 0.6
        showGrid = true
        language = .systemMatch
        appearance = .dark
        rephasePlan = RephasePlan()
        sleepGoal = .generalHealthDefault   // was missing
        hasCompletedOnboarding = false
        hasShownWelcome = false
        chronotypeResult = nil
        hasCompletedChronotype = false
        jetLagPlan = nil
        notificationsEnabled = false        // was missing
        contextBlocks = []
        contextBlocksEnabled = false
        contextBufferMinutes = 60.0
        conflictHistory = []
        predictionEnabled = false
        predictionOverlayEnabled = false
        mlPredictionEnabled = true
        latestPrediction = nil
        predictionHistory = []
        hasBootstrappedPredictions = false
        lastModelTrainedDate = nil
        modelTrainingSampleCount = 0
        streakHistory = StreakData()
        previousWeekStats = nil
        previousCompositeScore = nil
        microHabitCompletions = [:]
        llmEnabled = false
        chatHistory = []
        records = []
        analysis = AnalysisResult()
        scheduleConflicts = []
        hrvData = []                        // was missing
    }

    // MARK: - Persistence

    private let storageKey = "spiral-journey-store"
    static let appGroupID = "group.xaron.spiral-journey-project"
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    /// Increment this when the onboarding flow changes significantly.
    /// Any stored version below this number will replay the welcome + tutorial.
    private let currentOnboardingVersion = 1

    /// Schedule or cancel weekly digest notifications based on user preference.
    func updateWeeklyDigest() async {
        if notificationsEnabled {
            await NotificationManager.shared.scheduleWeeklyDigest(
                analysis: analysis,
                consistency: analysis.consistency
            )
        } else {
            await NotificationManager.shared.cancelWeeklyDigest()
        }
    }

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
        var notificationsEnabled: Bool?
        var contextBlocks: [ContextBlock]?
        var contextBlocksEnabled: Bool?
        var contextBufferMinutes: Double?
        var conflictHistory: [ConflictSnapshot]?
        var predictionEnabled: Bool?
        var predictionOverlayEnabled: Bool?
        var mlPredictionEnabled: Bool?
        var latestPrediction: PredictionOutput?
        var predictionHistory: [PredictionResult]?
        var hasBootstrappedPredictions: Bool?
        var lastModelTrainedDate: Date?
        var modelTrainingSampleCount: Int?
        // Enhanced coach
        var streakHistory: StreakData?
        var previousWeekStats: SleepStats?
        var previousCompositeScore: Int?
        var microHabitCompletions: [String: Bool]?
        // LLM chat
        var llmEnabled: Bool?
        var chatHistory: [ChatMessage]?
    }

    private func save() {
        guard !isSyncingFromCloud, !isLoading else { return }
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
            jetLagPlan: jetLagPlan,
            notificationsEnabled: notificationsEnabled,
            contextBlocks: contextBlocks,
            contextBlocksEnabled: contextBlocksEnabled,
            contextBufferMinutes: contextBufferMinutes,
            conflictHistory: conflictHistory,
            predictionEnabled: predictionEnabled,
            predictionOverlayEnabled: predictionOverlayEnabled,
            mlPredictionEnabled: mlPredictionEnabled,
            latestPrediction: latestPrediction,
            predictionHistory: predictionHistory,
            hasBootstrappedPredictions: hasBootstrappedPredictions,
            lastModelTrainedDate: lastModelTrainedDate,
            modelTrainingSampleCount: modelTrainingSampleCount,
            streakHistory: streakHistory,
            previousWeekStats: previousWeekStats,
            previousCompositeScore: previousCompositeScore,
            microHabitCompletions: microHabitCompletions,
            llmEnabled: llmEnabled,
            chatHistory: chatHistory
        )
        if let data = try? JSONEncoder().encode(stored) {
            sharedDefaults.set(data, forKey: storageKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Push settings snapshot to CloudKit (episodes/events are pushed at the call site).
        let now = Date()
        UserDefaults.standard.set(now, forKey: "spiral-journey-settings-modified-at")
        cloudSync?.enqueueSettingsSave(currentCloudSettings(modifiedAt: now))
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        // Prefer the shared App Group suite; migrate from standard if needed.
        var data = sharedDefaults.data(forKey: storageKey)
        if data == nil, let legacy = UserDefaults.standard.data(forKey: storageKey) {
            // First launch after migration — copy legacy data to shared suite.
            sharedDefaults.set(legacy, forKey: storageKey)
            data = legacy
        }
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        sleepEpisodes = stored.sleepEpisodes
        events = stored.events
        startDate = stored.startDate
        numDays = stored.numDays
        spiralType = stored.spiralType
        period = stored.period
        linkGrowthToTau = stored.linkGrowthToTau
        if let ds   = stored.depthScale  { depthScale = ds }
        if let grid = stored.showGrid    { showGrid = grid }
        if let lang = stored.language {
            // Migrate: if the stored language was set before the "System" option existed,
            // reset to .system so the app follows the device language going forward.
            // A UserDefaults flag marks that the user has explicitly chosen a language
            // after the System option was introduced.
            let hasExplicitChoice = sharedDefaults.bool(forKey: "userChoseLanguageExplicitly")
            language = (lang == .system || hasExplicitChoice) ? lang : .system
        }
        if let app  = stored.appearance  { appearance = app }
        if let rp   = stored.rephasePlan { rephasePlan = rp }
        if let sg   = stored.sleepGoal   { sleepGoal = sg }

        if let cr  = stored.chronotypeResult { chronotypeResult = cr }
        if let hcc = stored.hasCompletedChronotype { hasCompletedChronotype = hcc }
        if let jl  = stored.jetLagPlan { jetLagPlan = jl }
        if let ne  = stored.notificationsEnabled { notificationsEnabled = ne }
        if let cb  = stored.contextBlocks { contextBlocks = cb }
        if let cbe = stored.contextBlocksEnabled { contextBlocksEnabled = cbe }
        if let cbm = stored.contextBufferMinutes { contextBufferMinutes = cbm }
        if let ch  = stored.conflictHistory { conflictHistory = ch }
        if let pe  = stored.predictionEnabled { predictionEnabled = pe }
        if let poe = stored.predictionOverlayEnabled { predictionOverlayEnabled = poe }
        if let mpe = stored.mlPredictionEnabled { mlPredictionEnabled = mpe }
        if let lp  = stored.latestPrediction { latestPrediction = lp }
        if let ph  = stored.predictionHistory { predictionHistory = ph }
        if let hbp = stored.hasBootstrappedPredictions { hasBootstrappedPredictions = hbp }
        if let lmt = stored.lastModelTrainedDate { lastModelTrainedDate = lmt }
        if let mtc = stored.modelTrainingSampleCount { modelTrainingSampleCount = mtc }
        if let sh  = stored.streakHistory { streakHistory = sh }
        if let pws = stored.previousWeekStats { previousWeekStats = pws }
        if let pcs = stored.previousCompositeScore { previousCompositeScore = pcs }
        if let mhc = stored.microHabitCompletions { microHabitCompletions = mhc }
        if let le  = stored.llmEnabled { llmEnabled = le }
        if let ch  = stored.chatHistory { chatHistory = ch }

        // Only restore onboarding state if the stored version matches current.
        // If version is missing or outdated, the flags stay false → tutorial replays.
        let savedVersion = stored.onboardingVersion ?? 0
        if savedVersion >= currentOnboardingVersion {
            if let hco = stored.hasCompletedOnboarding { hasCompletedOnboarding = hco }
            if let hsw = stored.hasShownWelcome { hasShownWelcome = hsw }
        }
    }

    /// Write to local storage without pushing to CloudKit.
    /// Used when applying remote changes to prevent sync loops.
    private func saveLocalOnly() {
        isSyncingFromCloud = true
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
            jetLagPlan: jetLagPlan,
            notificationsEnabled: notificationsEnabled,
            contextBlocks: contextBlocks,
            contextBlocksEnabled: contextBlocksEnabled,
            contextBufferMinutes: contextBufferMinutes,
            conflictHistory: conflictHistory,
            predictionEnabled: predictionEnabled,
            predictionOverlayEnabled: predictionOverlayEnabled,
            mlPredictionEnabled: mlPredictionEnabled,
            latestPrediction: latestPrediction,
            predictionHistory: predictionHistory,
            hasBootstrappedPredictions: hasBootstrappedPredictions,
            lastModelTrainedDate: lastModelTrainedDate,
            modelTrainingSampleCount: modelTrainingSampleCount,
            streakHistory: streakHistory,
            previousWeekStats: previousWeekStats,
            previousCompositeScore: previousCompositeScore,
            microHabitCompletions: microHabitCompletions,
            llmEnabled: llmEnabled,
            chatHistory: chatHistory
        )
        if let data = try? JSONEncoder().encode(stored) {
            sharedDefaults.set(data, forKey: storageKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        isSyncingFromCloud = false
    }

    // MARK: - CloudKit Merge Methods

    /// Merge episodes received from CloudKit. Deduplicates by UUID; newer modifiedAt wins.
    func mergeCloudEpisodes(_ remote: [SleepEpisode]) {
        var changed = false
        for r in remote {
            if let idx = sleepEpisodes.firstIndex(where: { $0.id == r.id }) {
                sleepEpisodes[idx] = r
                changed = true
            } else {
                sleepEpisodes.append(r)
                changed = true
            }
        }
        if changed {
            sleepEpisodes.sort { $0.start < $1.start }
            saveLocalOnly()
            recompute()
        }
    }

    /// Merge events received from CloudKit. Deduplicates by UUID.
    func mergeCloudEvents(_ remote: [CircadianEvent]) {
        var changed = false
        for r in remote {
            if let idx = events.firstIndex(where: { $0.id == r.id }) {
                events[idx] = r
                changed = true
            } else {
                events.append(r)
                changed = true
            }
        }
        if changed {
            events.sort { $0.absoluteHour < $1.absoluteHour }
            saveLocalOnly()
        }
    }

    /// Apply deletions received from CloudKit.
    func applyCloudDeletions(episodeIDs: [UUID], eventIDs: [UUID]) {
        let epsBefore = sleepEpisodes.count
        let evtsBefore = events.count
        sleepEpisodes.removeAll { episodeIDs.contains($0.id) }
        events.removeAll { eventIDs.contains($0.id) }
        if sleepEpisodes.count != epsBefore || events.count != evtsBefore {
            saveLocalOnly()
            if sleepEpisodes.count != epsBefore { recompute() }
        }
    }

    /// Apply settings received from CloudKit (last-writer-wins by modifiedAt).
    func applyCloudSettings(_ remote: CloudSettings) {
        // Only apply if the remote is newer than any recent local change.
        // We track last-settings-modified via the dedicated UserDefaults key.
        let localModKey = "spiral-journey-settings-modified-at"
        let localMod = UserDefaults.standard.object(forKey: localModKey) as? Date ?? .distantPast
        guard remote.modifiedAt > localMod else { return }

        isSyncingFromCloud = true
        if let st = SpiralType(rawValue: remote.spiralType) { spiralType = st }
        period = remote.period
        linkGrowthToTau = remote.linkGrowthToTau
        depthScale = remote.depthScale
        showGrid = remote.showGrid
        if let lang = AppLanguage(rawValue: remote.language) { language = lang }
        if let app = AppAppearance(rawValue: remote.appearance) { appearance = app }
        if let data = remote.rephasePlanData,
           let rp = try? JSONDecoder().decode(RephasePlan.self, from: data) {
            rephasePlan = rp
        }
        if let data = remote.sleepGoalData,
           let sg = try? JSONDecoder().decode(SleepGoal.self, from: data) {
            sleepGoal = sg
        }
        // Only apply startDate/numDays if the remote epoch is earlier (more data).
        if remote.startDate < startDate { startDate = remote.startDate }
        if remote.numDays > numDays { numDays = remote.numDays }
        isSyncingFromCloud = false
        saveLocalOnly()
    }

    /// Snapshot current settings for CloudKit upload.
    func currentCloudSettings(modifiedAt: Date = Date()) -> CloudSettings {
        CloudSettings(
            startDate: startDate,
            numDays: numDays,
            spiralType: spiralType.rawValue,
            period: period,
            linkGrowthToTau: linkGrowthToTau,
            depthScale: depthScale,
            showGrid: showGrid,
            language: language.rawValue,
            appearance: appearance.rawValue,
            rephasePlanData: try? JSONEncoder().encode(rephasePlan),
            sleepGoalData: try? JSONEncoder().encode(sleepGoal),
            modifiedAt: modifiedAt
        )
    }
}
