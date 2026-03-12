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

    /// Called whenever new sleep data arrives in HealthKit (e.g. after a Watch sleep session).
    var onNewSleepData: (() -> Void)?
    private var observerQuery: HKObserverQuery?

    // MARK: - Authorization

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else {
            errorMessage = String(localized: "healthkit.error.notAvailable")
            return
        }
        let readTypes: Set<HKObjectType> = [sleepType]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
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
            DispatchQueue.main.async {
                self?.onNewSleepData?()
            }
            completionHandler()
        }
        observerQuery = query
        store.execute(query)
        // Enable background delivery so the callback fires even when the app is backgrounded.
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
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
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                // Only include actual sleep stages (not inBed).
                let sleepSamples = samples.filter { sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    return value != .inBed
                }

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

    /// Import HealthKit sleep data into the store, automatically adjusting startDate
    /// to the earliest detected sleep session. This fixes the common case where
    /// startDate = today but all sleep occurred yesterday or earlier.
    ///
    /// Returns the adjusted epoch so the caller can update store.startDate.
    func importAndAdjustEpoch(days: Int) async -> (episodes: [SleepEpisode], epoch: Date)? {
        guard isAuthorized, isAvailable else { return nil }
        let calendar = Calendar.current
        let end = Date()
        guard let searchStart = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }

        // First pass: raw fetch with a temporary epoch = searchStart to find all samples
        let rawEpisodes = await fetchSleepEpisodes(from: searchStart, to: end, epoch: searchStart)
        guard !rawEpisodes.isEmpty else { return nil }

        // Compute the real epoch: start of the day containing the earliest sleep
        let earliestAbsHour = rawEpisodes.map(\.start).min() ?? 0
        let earliestDate = searchStart.addingTimeInterval(earliestAbsHour * 3600)
        let realEpoch = calendar.startOfDay(for: earliestDate)

        // Second pass: re-fetch with the correct epoch so absolute hours are right
        let episodes = await fetchSleepEpisodes(from: searchStart, to: end, epoch: realEpoch)
        return (episodes, realEpoch)
    }
}

// MARK: - Date Helpers

private extension Date {
    /// Returns the absolute hours elapsed since the given epoch date (day 0 00:00).
    func absoluteHour(from epoch: Date) -> Double {
        timeIntervalSince(epoch) / 3600
    }
}
