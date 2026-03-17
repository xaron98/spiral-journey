import Foundation
import Observation
import SwiftData
import SpiralKit

/// Manages the SleepDNA profile lifecycle: loads cached profiles from SwiftData,
/// computes new profiles via `SleepDNAComputer`, and caches results.
@Observable @MainActor
final class SleepDNAService {

    // MARK: - Published State

    /// The most recently computed or loaded SleepDNA profile.
    private(set) var latestProfile: SleepDNAProfile?

    /// Whether a computation is currently in progress.
    private(set) var isComputing: Bool = false

    /// When the latest profile was computed (mirrors `latestProfile?.computedAt`).
    private(set) var lastComputedAt: Date?

    /// Human-readable error from the last computation attempt, if any.
    private(set) var error: String?

    // MARK: - Private

    private let computer = SleepDNAComputer()

    // MARK: - Load Cached

    /// Fetch the latest `SDSleepDNASnapshot` from SwiftData and decode it
    /// into a `SleepDNAProfile`, populating `latestProfile`.
    func loadCachedProfile(context: ModelContext) {
        let descriptor = FetchDescriptor<SDSleepDNASnapshot>(
            sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
        )

        guard let snapshot = (try? context.fetch(descriptor))?.first,
              let jsonData = snapshot.profileJSON else {
            return
        }

        do {
            let profile = try JSONDecoder().decode(SleepDNAProfile.self, from: jsonData)
            latestProfile = profile
            lastComputedAt = snapshot.computedAt
            error = nil
        } catch {
            self.error = "Failed to decode cached profile: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh

    /// Compute a new profile only if no snapshot exists from today.
    func refreshIfNeeded(store: SpiralStore, context: ModelContext) async {
        if let last = lastComputedAt, Calendar.current.isDateInToday(last) {
            return
        }
        await computeAndSave(store: store, context: context)
    }

    /// Always compute a fresh profile (for pull-to-refresh).
    func forceRefresh(store: SpiralStore, context: ModelContext) async {
        await computeAndSave(store: store, context: context)
    }

    // MARK: - Core Pipeline

    private func computeAndSave(store: SpiralStore, context: ModelContext) async {
        guard !isComputing else { return }

        isComputing = true
        error = nil

        do {
            // Load existing BLOSUM weights if available
            let existingBLOSUM = loadExistingBLOSUM(context: context)

            // Gather inputs from SpiralStore
            let records = store.records
            let events = store.events
            let chronotype = store.chronotypeResult
            let goalDuration = store.sleepGoal.targetDuration
            let period = store.period

            // Compute profile off the main actor
            let profile = try await computer.compute(
                records: records,
                events: events,
                chronotype: chronotype,
                goalDuration: goalDuration,
                period: period,
                existingBLOSUM: existingBLOSUM
            )

            // Save snapshot to SwiftData
            saveSnapshot(profile: profile, context: context)

            // Update BLOSUM if full tier
            if profile.tier == .full {
                saveBLOSUM(profile.scoringMatrix, context: context)
            }

            latestProfile = profile
            lastComputedAt = profile.computedAt
            error = nil
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            self.error = error.localizedDescription
        }

        isComputing = false
    }

    // MARK: - SwiftData Helpers

    /// Load the most recent persisted SleepBLOSUM weights, if any.
    private func loadExistingBLOSUM(context: ModelContext) -> SleepBLOSUM? {
        let descriptor = FetchDescriptor<SDSleepBLOSUM>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        guard let stored = (try? context.fetch(descriptor))?.first,
              let weights = try? JSONDecoder().decode([Double].self, from: Data(stored.weightsJSON.utf8)),
              weights.count == 16 else {
            return nil
        }

        var blosum = SleepBLOSUM.initial
        blosum.weights = weights
        return blosum
    }

    /// Delete old snapshots and save a new one (keep only the latest).
    private func saveSnapshot(profile: SleepDNAProfile, context: ModelContext) {
        // Delete all existing snapshots
        do {
            let existing = try context.fetch(FetchDescriptor<SDSleepDNASnapshot>())
            for old in existing {
                context.delete(old)
            }
        } catch {
            // Non-fatal: proceed with saving
        }

        // Encode profile to JSON
        let jsonData = try? JSONEncoder().encode(profile)

        let snapshot = SDSleepDNASnapshot(
            computedAt: profile.computedAt,
            tier: profile.tier.rawValue,
            dataWeeks: profile.dataWeeks,
            profileJSON: jsonData
        )
        context.insert(snapshot)

        try? context.save()
    }

    /// Save or update the persisted BLOSUM weights.
    private func saveBLOSUM(_ blosum: SleepBLOSUM, context: ModelContext) {
        // Delete existing BLOSUM entries
        do {
            let existing = try context.fetch(FetchDescriptor<SDSleepBLOSUM>())
            for old in existing {
                context.delete(old)
            }
        } catch {
            // Non-fatal
        }

        let weightsJSON = (try? String(data: JSONEncoder().encode(blosum.weights), encoding: .utf8)) ?? "[]"

        let record = SDSleepBLOSUM(
            updatedAt: Date(),
            weightsJSON: weightsJSON
        )
        context.insert(record)

        try? context.save()
    }
}
