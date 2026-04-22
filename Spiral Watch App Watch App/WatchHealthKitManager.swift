import Foundation
import HealthKit
import SpiralKit

/// Manages HealthKit authorization and sleep data queries on watchOS.
/// Mirrors the iOS HealthKitManager but runs independently on the Watch
/// so the app works without a paired iPhone.
@MainActor
final class WatchHealthKitManager {

    static let shared = WatchHealthKitManager()

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    /// Persisted across launches so `refreshFromHealthKit()` works immediately
    /// when the watch face or complication wakes the app, before `setupHealthKit()`
    /// has a chance to call `requestAuthorization()` again.
    var isAuthorized: Bool {
        get { UserDefaults.standard.bool(forKey: "watchHKAuthorized") }
        set { UserDefaults.standard.set(newValue, forKey: "watchHKAuthorized") }
    }
    private var observerQuery: HKObserverQuery?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var sleepAnchor: HKQueryAnchor?

    /// Called whenever HealthKit delivers new sleep data.
    var onNewSleepData: (() -> Void)?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else {
            #if DEBUG
            print("[WatchHK] HK not available — cannot authorize")
            #endif
            return
        }
        let readTypes: Set<HKObjectType> = [sleepType]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            #if DEBUG
            print("[WatchHK] Authorization succeeded, isAuthorized=true")
            #endif
        } catch {
            #if DEBUG
            print("[WatchHK] Authorization error: \(error)")
            #endif
            // Authorization declined or unavailable — continue without HealthKit.
        }
    }

    // MARK: - Observer Query

    /// Start listening for new sleep samples. Fires `onNewSleepData` even in background.
    func startObservingNewSleep() {
        guard isAvailable, observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            Task { @MainActor [weak self] in
                self?.onNewSleepData?()
            }
            completionHandler()
        }
        observerQuery = query
        store.execute(query)
        enableBackgroundDeliveryWithRetry()
    }

    /// Retry background delivery up to 3 times (same as iOS).
    private func enableBackgroundDeliveryWithRetry(attempts: Int = 3) {
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { [weak self] success, error in
            if !success, let self, attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.enableBackgroundDeliveryWithRetry(attempts: attempts - 1)
                }
            }
            #if DEBUG
            if let error { print("[WatchHK] Background delivery error: \(error.localizedDescription)") }
            #endif
        }
    }

    // MARK: - Anchored Query (more reliable than observer)

    /// Start an anchored query that fires on every new sleep sample.
    func startAnchoredSleepQuery() {
        guard isAvailable, anchoredQuery == nil else { return }
        #if DEBUG
        print("[WatchHK-Anchor] Starting anchored query")
        #endif

        let query = HKAnchoredObjectQuery(
            type: sleepType,
            predicate: nil,
            anchor: sleepAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, _, _, newAnchor, error in
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                self?.sleepAnchor = newAnchor
            }
            // Initial fetch — don't trigger callback (loadData already ran)
        }

        query.updateHandler = { [weak self] _, newSamples, _, newAnchor, error in
            guard error == nil else { return }
            guard let samples = newSamples, !samples.isEmpty else { return }
            #if DEBUG
            print("[WatchHK-Anchor] UPDATE: \(samples.count) new samples!")
            #endif
            Task { @MainActor [weak self] in
                self?.sleepAnchor = newAnchor
                self?.onNewSleepData?()
            }
        }

        anchoredQuery = query
        store.execute(query)
    }

    // MARK: - Sleep Data Query

    /// Fetch recent sleep episodes from HealthKit for the last `days` days.
    /// - Parameter epoch: The store's startDate — used as day-0 for absolute hour calculation.
    /// - Parameter searchFromEpoch: If true, search from `epoch` instead of `days` ago (for initial epoch discovery).
    func fetchRecentSleepEpisodes(days: Int = 30, epoch: Date, searchFromEpoch: Bool = false) async -> [SleepEpisode] {
        guard isAvailable, isAuthorized else {
            #if DEBUG
            print("[WatchHK] fetchRecentSleepEpisodes: guard failed — isAvailable=\(isAvailable) isAuthorized=\(isAuthorized)")
            #endif
            return []
        }
        let end = Date()
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -days, to: end) ?? epoch
        let searchStart = searchFromEpoch ? min(epoch, recentStart) : recentStart
        #if DEBUG
        print("[WatchHK] Querying HK sleep from \(searchStart) to \(end), epoch=\(epoch)")
        #endif
        return await fetchSleepEpisodes(from: searchStart, to: end, epoch: epoch)
    }

    private func fetchSleepEpisodes(from startDate: Date, to endDate: Date, epoch: Date) async -> [SleepEpisode] {
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
                if let error = error {
                    #if DEBUG
                    print("[WatchHK] HKSampleQuery error: \(error)")
                    #endif
                }
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                #if DEBUG
                print("[WatchHK] Raw samples from HK: \(samples.count)")
                #endif
                // Only actual sleep stages — skip "inBed" which is not a sleep phase.
                let sleepSamples = samples.filter {
                    HKCategoryValueSleepAnalysis(rawValue: $0.value) != .inBed
                }
                #if DEBUG
                print("[WatchHK] After filtering inBed: \(sleepSamples.count) sleep samples")
                #endif
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
                    default:           phase = nil
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
}

// MARK: - Date Helper

private extension Date {
    func absoluteHour(from epoch: Date) -> Double {
        timeIntervalSince(epoch) / 3600
    }
}
