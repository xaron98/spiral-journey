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
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    var isAuthorized = false
    private var observerQuery: HKObserverQuery?

    /// Called whenever HealthKit delivers new sleep data.
    var onNewSleepData: (() -> Void)?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }
        let readTypes: Set<HKObjectType> = [sleepType]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            // Authorization declined or unavailable — continue without HealthKit.
        }
    }

    // MARK: - Observer Query

    /// Start listening for new sleep samples. Fires `onNewSleepData` even in background.
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
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Sleep Data Query

    /// Fetch recent sleep episodes from HealthKit for the last `days` days.
    /// - Parameter epoch: The store's startDate — used as day-0 for absolute hour calculation.
    func fetchRecentSleepEpisodes(days: Int = 30, epoch: Date) async -> [SleepEpisode] {
        guard isAvailable, isAuthorized else { return [] }
        let end = Date()
        let calendar = Calendar.current
        let searchStart = min(epoch, calendar.date(byAdding: .day, value: -days, to: end) ?? epoch)
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
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                // Only actual sleep stages — skip "inBed" which is not a sleep phase.
                let sleepSamples = samples.filter {
                    HKCategoryValueSleepAnalysis(rawValue: $0.value) != .inBed
                }
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
