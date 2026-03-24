import Foundation
import Observation
import HealthKit
import SpiralKit

/// Manages HealthKit authorization and sleep data queries.
@MainActor
@Observable
final class HealthKitManager {

    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    var isAuthorized = false
    var errorMessage: String? = nil

    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

    // Fitness & health types for full-day chronobiograph
    private static var fitnessReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.environmentalAudioExposure),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.mindfulSession),
            HKWorkoutType.workoutType(),
        ]
        // iOS 17+
        if #available(iOS 17.0, *) {
            types.insert(HKQuantityType(.timeInDaylight))
            types.insert(HKQuantityType(.appleSleepingWristTemperature))
        }
        // Menstrual cycle
        types.insert(HKCategoryType(.menstrualFlow))
        return types
    }

    init() {
        // Restore authorized state on re-launch without showing a dialog.
        // HKAuthorizationStatus.sharingAuthorized is used for write types; for read types
        // HealthKit never reveals the true status for privacy — but .notDetermined means
        // the dialog has never been shown, so we can infer "previously shown = authorized".
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let tempStore = HKHealthStore()
        let status = tempStore.authorizationStatus(for: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        // .notDetermined = never asked; anything else = user was asked, treat as authorized
        // so imports are always attempted (fetchSleepEpisodes returns [] if truly denied).
        if status != .notDetermined {
            isAuthorized = true
        }
        // Restore persisted anchor so anchored queries resume from last position.
        restoreAnchor()
    }

    /// Called whenever new sleep data arrives in HealthKit (e.g. after a Watch sleep session).
    var onNewSleepData: (() -> Void)?
    private var observerQuery: HKObserverQuery?
    /// Prevents concurrent calls to importAndAdjustEpoch (e.g. foreground + observer firing together).
    private var isImporting = false
    /// When true, another import is queued while one is already running.
    /// Ensures observer callbacks aren't silently dropped.
    private var needsRetryAfterImport = false

    /// Debounce task for coalescing rapid HealthKit callbacks (observer + anchored).
    private var debounceTask: Task<Void, Never>?
    /// Debounce interval for HealthKit callbacks — coalesces multiple rapid notifications.
    private let debounceInterval: Duration = .milliseconds(500)

    // MARK: - Anchored Object Query (primary live update mechanism)
    private var sleepAnchor: HKQueryAnchor? {
        didSet {
            guard !isRestoringAnchor else { return }
            persistAnchor()
        }
    }
    private var anchoredQuery: HKAnchoredObjectQuery?
    /// Prevents persistAnchor() from firing during restoreAnchor() (avoid writing back the same data).
    private var isRestoringAnchor = false

    /// UserDefaults key for persisting the HKQueryAnchor between launches.
    private static let anchorKey = "spiral-journey-hk-sleep-anchor"

    /// Save the current anchor to UserDefaults so it survives app restarts.
    /// On next launch the anchored query starts from where it left off
    /// instead of re-fetching the entire history.
    private func persistAnchor() {
        guard let anchor = sleepAnchor else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: anchor, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        } catch {
            print("[HK] Failed to persist anchor: \(error)")
        }
    }

    /// Restore a previously saved anchor from UserDefaults.
    private func restoreAnchor() {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return }
        do {
            isRestoringAnchor = true
            sleepAnchor = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self, from: data)
            isRestoringAnchor = false
            print("[HK] Restored persisted anchor")
        } catch {
            isRestoringAnchor = false
            print("[HK] Failed to restore anchor: \(error)")
        }
    }

    // MARK: - Authorization

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else {
            errorMessage = String(localized: "healthkit.error.notAvailable")
            return
        }
        let readTypes = Self.fitnessReadTypes
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // requestAuthorization always succeeds (even if user denies) — HealthKit
            // hides the actual read permission for privacy. Mark as authorized so that
            // imports are always attempted; fetchSleepEpisodes returns [] if truly denied.
            isAuthorized = true
        } catch {
            errorMessage = String(format: String(localized: "healthkit.error.accessFailed"), error.localizedDescription)
        }
    }

    // MARK: - Observer Query (live updates from Watch / Health app)

    /// Start listening for new sleep data written to HealthKit.
    /// Fires `onNewSleepData` whenever the Watch (or any other source) adds sleep samples.
    func startObservingNewSleep() {
        guard isAvailable, observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            Task { @MainActor [weak self] in
                self?.debouncedNotify()
            }
            completionHandler()
        }
        observerQuery = query
        store.execute(query)
        // Enable background delivery so the callback fires even when the app is backgrounded.
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { success, error in
            if let error {
                print("[HealthKit] Background delivery failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Anchored Sleep Query

    /// Start an anchored object query for live sleep data updates.
    /// More reliable than HKObserverQuery — delivers new samples directly
    /// via the updateHandler whenever HealthKit receives new sleep data.
    func startAnchoredSleepQuery(epoch: Date, onNewEpisodes: @escaping ([SleepEpisode]) -> Void) {
        guard isAvailable, anchoredQuery == nil else { return }

        print("[HK-Anchor] Starting anchored query, existing anchor: \(String(describing: sleepAnchor))")

        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: nil,
            anchor: sleepAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, newSamples, _, newAnchor, error in
            if let error { print("[HK-Anchor] initial error: \(error)"); return }
            print("[HK-Anchor] initial fetch: \(newSamples?.count ?? 0) samples")
            Task { @MainActor [weak self] in
                self?.sleepAnchor = newAnchor
                self?.processAnchoredSamples(newSamples, epoch: epoch, callback: onNewEpisodes)
            }
        }

        // updateHandler fires on EVERY new sample added to HealthKit
        query.updateHandler = { [weak self] _, newSamples, _, newAnchor, error in
            if let error { print("[HK-Anchor] update error: \(error)"); return }
            print("[HK-Anchor] UPDATE: \(newSamples?.count ?? 0) new samples received!")
            Task { @MainActor [weak self] in
                self?.sleepAnchor = newAnchor
                self?.processAnchoredSamples(newSamples, epoch: epoch, callback: onNewEpisodes)
            }
        }

        anchoredQuery = query
        store.execute(query)
    }

    /// Convert raw HKSamples from the anchored query into SleepEpisodes.
    /// Same filtering/conversion logic as fetchSleepEpisodes, but operates
    /// on a pre-delivered sample array instead of running a new query.
    /// Must be called on the main actor (dispatched from query callbacks).
    private func processAnchoredSamples(
        _ samples: [HKSample]?,
        epoch: Date,
        callback: @escaping ([SleepEpisode]) -> Void
    ) {
        guard let samples = samples as? [HKCategorySample], !samples.isEmpty else { return }

        // Filter out inBed, convert to SleepEpisode
        let sleepSamples = samples.filter { sample in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            return value != .inBed
        }

        var episodes: [SleepEpisode] = []
        for sample in sleepSamples {
            let absStart = sample.startDate.absoluteHour(from: epoch)
            let absEnd = sample.endDate.absoluteHour(from: epoch)
            guard absEnd > absStart, absStart >= 0 else { continue }

            let hkValue = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            let phase: SleepPhase?
            switch hkValue {
            case .asleepDeep:  phase = .deep
            case .asleepREM:   phase = .rem
            case .asleepCore:  phase = .light
            case .awake:       phase = .awake
            default:           phase = nil
            }

            episodes.append(SleepEpisode(
                start: absStart, end: absEnd, source: .healthKit,
                healthKitSampleID: sample.uuid.uuidString, phase: phase
            ))
        }

        if !episodes.isEmpty {
            callback(episodes)
        }
    }

    // MARK: - Debounce

    /// Coalesce rapid HealthKit callbacks into a single notification.
    /// Observer and anchored queries can fire simultaneously — this ensures
    /// only one `onNewSleepData` call happens per 500ms window.
    private func debouncedNotify() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.onNewSleepData?()
        }
    }

    // MARK: - Sleep Data Query

    /// Fetch sleep episodes from HealthKit for the given date range.
    /// - Parameter epoch: The store's startDate — used as day-0 for absolute hour calculation.
    ///   All returned SleepEpisode.start/end values are hours elapsed since this date.
    func fetchSleepEpisodes(from startDate: Date, to endDate: Date, epoch: Date) async -> [SleepEpisode] {
        guard isAvailable else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    print("[HK] fetchSleepEpisodes error: \(error)")
                }
                guard let samples = samples as? [HKCategorySample] else {
                    print("[HK] fetchSleepEpisodes: samples cast failed, count=\(samples?.count ?? -1)")
                    continuation.resume(returning: [])
                    return
                }
                print("[HK] fetchSleepEpisodes: raw samples=\(samples.count)")

                // Only include actual sleep stages (not inBed).
                let sleepSamples = samples.filter { sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    return value != .inBed
                }
                print("[HK] fetchSleepEpisodes: after inBed filter=\(sleepSamples.count)")

                // Convert each HealthKit sample to a SleepEpisode preserving its phase.
                // Apple Watch records short per-stage samples (deep/core/REM/awake) — keeping
                // them separate lets ManualDataConverter render each phase with its own color.
                // Deduplication uses sample UUID so re-fetches are stable.
                let sorted = sleepSamples.sorted { $0.startDate < $1.startDate }
                var episodes: [SleepEpisode] = []

                for sample in sorted {
                    let absStart = sample.startDate.absoluteHour(from: epoch)
                    let absEnd   = sample.endDate.absoluteHour(from: epoch)
                    guard absEnd > absStart, absStart >= 0 else { continue }

                    let hkValue = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    let phase: SleepPhase?
                    switch hkValue {
                    case .asleepDeep:  phase = .deep
                    case .asleepREM:   phase = .rem
                    case .asleepCore:  phase = .light
                    case .awake:       phase = .awake
                    default:           phase = nil  // asleepUnspecified → falls back to .deep
                    }

                    episodes.append(SleepEpisode(
                        start: absStart,
                        end:   absEnd,
                        source: .healthKit,
                        healthKitSampleID: sample.uuid.uuidString,
                        phase: phase
                    ))
                }
                continuation.resume(returning: episodes)
            }
            self.store.execute(query)
        }
    }

    /// Re-fetch recent sleep data and call the given handler with results.
    /// Convenience wrapper used by the observer callback and manual refresh button.
    func refreshRecentSleep(days: Int, epoch: Date) async -> [SleepEpisode] {
        guard isAuthorized else { return [] }
        return await fetchRecentSleepEpisodes(days: days, epoch: epoch)
    }

    /// Fetch sleep episodes for the last N days, anchored to the given epoch (store.startDate).
    func fetchRecentSleepEpisodes(days: Int = 30, epoch: Date = Date()) async -> [SleepEpisode] {
        let calendar = Calendar.current
        let end   = Date()
        // Search from epoch or (end - days), whichever is earlier, to capture all data
        let searchStart = min(epoch, calendar.date(byAdding: .day, value: -days, to: end) ?? epoch)
        return await fetchSleepEpisodes(from: searchStart, to: end, epoch: epoch)
    }

    /// Maximum number of days to search back in HealthKit for sleep data.
    /// Using 365 days ensures we capture a full year of history regardless of
    /// how many days the user has configured to display in the spiral.
    static let maxImportDays = 365

    /// Import HealthKit sleep data into the store, automatically adjusting startDate
    /// to the earliest detected sleep session. Always searches back up to maxImportDays
    /// so that users with months of historical data get it all — independent of numDays
    /// (which only controls how many days are displayed in the spiral).
    ///
    /// Returns the adjusted epoch so the caller can update store.startDate.
    func importAndAdjustEpoch() async -> (episodes: [SleepEpisode], epoch: Date)? {
        guard isAuthorized, isAvailable else {
            print("[HK] importAndAdjustEpoch: not authorized or not available")
            return nil
        }
        guard !isImporting else {
            // Don't drop the request — mark for retry once the current import finishes.
            // This prevents lost observer callbacks when foreground + observer overlap.
            print("[HK] importAndAdjustEpoch: already in progress, queuing retry")
            needsRetryAfterImport = true
            return nil
        }
        isImporting = true
        let importStart = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - importStart
            print("[HK] importAndAdjustEpoch took \(String(format: "%.2f", elapsed))s")
            isImporting = false
            // If another request came in while we were importing, fire a retry
            // so freshly synced Watch data isn't missed.
            if needsRetryAfterImport {
                needsRetryAfterImport = false
                Task { @MainActor in
                    self.onNewSleepData?()
                }
            }
        }
        let calendar = Calendar.current
        let end = Date()
        guard let searchStart = calendar.date(byAdding: .day, value: -Self.maxImportDays, to: end) else { return nil }
        print("[HK] searching from \(searchStart) to \(end)")

        // First pass: raw fetch with a temporary epoch = searchStart to find all samples
        let rawEpisodes = await fetchSleepEpisodes(from: searchStart, to: end, epoch: searchStart)
        print("[HK] first pass: \(rawEpisodes.count) episodes")
        guard !rawEpisodes.isEmpty else { return nil }

        // Compute the real epoch: start of the day containing the earliest sleep
        let earliestAbsHour = rawEpisodes.map(\.start).min() ?? 0
        let earliestDate = searchStart.addingTimeInterval(earliestAbsHour * 3600)
        let realEpoch = calendar.startOfDay(for: earliestDate)
        print("[HK] realEpoch: \(realEpoch)  (earliestAbsHour=\(earliestAbsHour)h, earliestDate=\(earliestDate))")

        // Second pass: re-fetch with the correct epoch so absolute hours are right
        let episodes = await fetchSleepEpisodes(from: searchStart, to: end, epoch: realEpoch)
        print("[HK] second pass: \(episodes.count) episodes, returning epoch=\(realEpoch)")
        return (episodes, realEpoch)
    }

    /// Incremental fetch: only queries the last 3 days from HealthKit and returns
    /// episodes whose sample UUID is not yet in `knownIDs`. Much cheaper than a
    /// full 365-day import — used by the periodic poll and observer callback.
    func fetchRecentNewEpisodes(epoch: Date, knownIDs: Set<String>) async -> [SleepEpisode] {
        guard isAvailable, isAuthorized else { return [] }
        let fetchStart = CFAbsoluteTimeGetCurrent()
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -3, to: end) else { return [] }

        let recent = await fetchSleepEpisodes(from: start, to: end, epoch: epoch)
        let newOnly = recent.filter { ep in
            guard let hkID = ep.healthKitSampleID else { return true }
            return !knownIDs.contains(hkID)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - fetchStart
        print("[HK] incremental fetch took \(String(format: "%.2f", elapsed))s — \(newOnly.count) new of \(recent.count) recent")
        return newOnly
    }

    // MARK: - HRV Data Query

    /// Fetch nightly HRV (SDNN) samples for the given date range.
    /// Groups samples by calendar day and computes mean SDNN per night.
    func fetchNightlyHRV(days: Int = 30) async -> [NightlyHRV] {
        guard isAvailable, isAuthorized else { return [] }

        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                // Group by calendar day
                var dayBuckets: [Date: [Double]] = [:]
                for sample in samples {
                    let dayStart = calendar.startOfDay(for: sample.startDate)
                    let sdnn = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    dayBuckets[dayStart, default: []].append(sdnn)
                }

                // Convert to NightlyHRV
                let results = dayBuckets.map { (date, values) in
                    let mean = values.reduce(0, +) / Double(values.count)
                    return NightlyHRV(date: date, meanSDNN: mean, sampleCount: values.count)
                }
                .sorted { $0.date < $1.date }

                continuation.resume(returning: results)
            }
            self.store.execute(query)
        }
    }
    // MARK: - Fitness Data Fetch Methods

    /// Fetch hourly step counts for a given date (24 values).
    func fetchHourlySteps(for date: Date) async -> [Double] {
        guard isAvailable, isAuthorized else { return Array(repeating: 0, count: 24) }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return Array(repeating: 0, count: 24)
        }

        let stepType = HKQuantityType(.stepCount)
        let interval = DateComponents(hour: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var hourly = Array(repeating: 0.0, count: 24)
                results?.enumerateStatistics(from: startOfDay, to: endOfDay) { stats, _ in
                    let hour = calendar.component(.hour, from: stats.startDate)
                    hourly[hour] = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                }
                continuation.resume(returning: hourly)
            }
            self.store.execute(query)
        }
    }

    /// Fetch resting heart rate and hour of minimum HR for a date.
    func fetchHeartRateData(for date: Date) async -> (restingHR: Double?, nadirHour: Double?) {
        guard isAvailable, isAuthorized else { return (nil, nil) }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return (nil, nil) }

        // Resting HR
        let restingType = HKQuantityType(.restingHeartRate)
        let restingPredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let restingHR: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: restingType, quantitySamplePredicate: restingPredicate, options: .discreteAverage) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }
            self.store.execute(query)
        }

        // HR nadir (minimum hour)
        let hrType = HKQuantityType(.heartRate)
        let hrPredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let nadirHour: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: hrPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                var minBPM = Double.infinity
                var minHour = 0.0
                for s in samples {
                    let bpm = s.quantity.doubleValue(for: bpmUnit)
                    if bpm < minBPM {
                        minBPM = bpm
                        let comps = calendar.dateComponents([.hour, .minute], from: s.startDate)
                        minHour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
                    }
                }
                continuation.resume(returning: minHour)
            }
            self.store.execute(query)
        }

        return (restingHR, nadirHour)
    }

    /// Fetch wrist temperature deviation for a date (iOS 17+).
    func fetchWristTemperature(for date: Date) async -> Double? {
        guard isAvailable, isAuthorized else { return nil }
        guard #available(iOS 17.0, *) else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        let tempType = HKQuantityType(.appleSleepingWristTemperature)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: tempType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let mean = samples.map { $0.quantity.doubleValue(for: .degreeCelsius()) }.reduce(0, +) / Double(samples.count)
                continuation.resume(returning: mean)
            }
            self.store.execute(query)
        }
    }

    /// Fetch daylight exposure minutes for a date (iOS 17+).
    func fetchDaylightMinutes(for date: Date) async -> Double? {
        guard isAvailable, isAuthorized else { return nil }
        guard #available(iOS 17.0, *) else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        let type = HKQuantityType(.timeInDaylight)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let minutes = stats?.sumQuantity()?.doubleValue(for: .minute())
                continuation.resume(returning: minutes)
            }
            self.store.execute(query)
        }
    }

    /// Fetch exercise minutes for a date.
    func fetchExerciseMinutes(for date: Date) async -> Double {
        guard isAvailable, isAuthorized else { return 0 }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }

        let type = HKQuantityType(.appleExerciseTime)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
            }
            self.store.execute(query)
        }
    }

    /// Fetch active calories for a date.
    func fetchActiveCalories(for date: Date) async -> Double {
        guard isAvailable, isAuthorized else { return 0 }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }

        let type = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            self.store.execute(query)
        }
    }

    /// Fetch menstrual flow for a date (nil if not tracked).
    func fetchMenstrualFlow(for date: Date) async -> Int? {
        guard isAvailable, isAuthorized else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        let type = HKCategoryType(.menstrualFlow)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                guard let sample = samples?.first as? HKCategorySample else {
                    continuation.resume(returning: nil)
                    return
                }
                // HKCategoryValueMenstrualFlow: 1=unspecified, 2=light, 3=medium, 4=heavy
                let flow = max(0, sample.value - 1) // map to 0-3
                continuation.resume(returning: flow)
            }
            self.store.execute(query)
        }
    }

    /// Fetch a complete DayHealthProfile for a given date.
    func fetchDayHealthProfile(for date: Date, dayIndex: Int) async -> DayHealthProfile {
        let hourlySteps = await fetchHourlySteps(for: date)
        let totalSteps = Int(hourlySteps.reduce(0, +))
        let exerciseMin = await fetchExerciseMinutes(for: date)
        let activeCal = await fetchActiveCalories(for: date)
        let (restingHR, nadirHour) = await fetchHeartRateData(for: date)
        let wristTemp = await fetchWristTemperature(for: date)
        let daylight = await fetchDaylightMinutes(for: date)
        let menstrual = await fetchMenstrualFlow(for: date)

        // Get nocturnal HRV for this specific date
        let hrvForDate = await fetchNightlyHRV(days: 2)
        let calendar = Calendar.current
        let todayHRV = hrvForDate.first(where: { calendar.isDate($0.date, inSameDayAs: date) })

        return DayHealthProfileBuilder.build(
            day: dayIndex,
            date: date,
            hourlySteps: hourlySteps,
            totalSteps: totalSteps,
            exerciseMinutes: exerciseMin,
            activeCalories: activeCal,
            restingHR: restingHR,
            avgNocturnalHRV: todayHRV?.meanSDNN,
            hrNadirHour: nadirHour,
            wristTempDeviation: wristTemp,
            daylightMinutes: daylight,
            menstrualFlow: menstrual
        )
    }
}

// MARK: - Date Helpers

private extension Date {
    /// Returns the absolute hours elapsed since the given epoch date (day 0 00:00).
    func absoluteHour(from epoch: Date) -> Double {
        timeIntervalSince(epoch) / 3600
    }
}
