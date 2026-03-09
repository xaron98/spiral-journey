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

                // Merge overlapping/adjacent samples into contiguous episodes.
                let sorted = sleepSamples.sorted { $0.startDate < $1.startDate }
                var episodes: [SleepEpisode] = []

                for sample in sorted {
                    // Compute hours relative to the store's epoch (day 0 = store.startDate)
                    let absStart = sample.startDate.absoluteHour(from: epoch)
                    let absEnd   = sample.endDate.absoluteHour(from: epoch)
                    guard absEnd > absStart, absStart >= 0 else { continue }

                    // Merge if gap to previous episode < 30 min
                    if let last = episodes.last, absStart - last.end < 0.5 {
                        episodes[episodes.count - 1] = SleepEpisode(
                            id:    last.id,
                            start: last.start,
                            end:   max(last.end, absEnd),
                            source: .healthKit,
                            healthKitSampleID: last.healthKitSampleID
                        )
                    } else {
                        episodes.append(SleepEpisode(
                            start: absStart,
                            end:   absEnd,
                            source: .healthKit,
                            healthKitSampleID: sample.uuid.uuidString
                        ))
                    }
                }
                continuation.resume(returning: episodes)
            }
            self.store.execute(query)
        }
    }

    /// Fetch sleep episodes for the last N days, anchored to the given epoch (store.startDate).
    func fetchRecentSleepEpisodes(days: Int = 30, epoch: Date = Date()) async -> [SleepEpisode] {
        let calendar = Calendar.current
        let end   = Date()
        // Search from epoch or (end - days), whichever is earlier, to capture all data
        let searchStart = min(epoch, calendar.date(byAdding: .day, value: -days, to: end) ?? epoch)
        return await fetchSleepEpisodes(from: searchStart, to: end, epoch: epoch)
    }
}

// MARK: - Date Helpers

private extension Date {
    /// Returns the absolute hours elapsed since the given epoch date (day 0 00:00).
    func absoluteHour(from epoch: Date) -> Double {
        timeIntervalSince(epoch) / 3600
    }
}
