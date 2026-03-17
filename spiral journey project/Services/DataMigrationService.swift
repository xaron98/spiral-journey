import Foundation
import SwiftData
import SpiralKit
import os.log

// MARK: - DataMigrationService

/// One-shot migration from UserDefaults/JSON (SpiralStore) to SwiftData.
///
/// Runs on first launch after the SwiftData stack is available. The service:
///  1. Checks a UserDefaults flag (`swiftDataMigrationCompleted`).
///  2. Reads all migratable data from `SpiralStore`.
///  3. Inserts corresponding SwiftData models via batch insert.
///  4. Verifies counts and spot-checks first/last records.
///  5. Marks migration complete on success; keeps JSON on failure so the
///     next launch can retry.
@MainActor
enum DataMigrationService {

    // MARK: - Public

    private static let migrationKey = "swiftDataMigrationCompleted"
    private static let logger = Logger(subsystem: "com.xaron.spiral-journey", category: "Migration")

    /// Run the JSON-to-SwiftData migration if it hasn't completed yet.
    ///
    /// Call this from a `.task {}` modifier in the app entry point.
    /// Safe to call multiple times -- returns immediately if already migrated.
    static func migrateIfNeeded(store: SpiralStore, container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            logger.info("SwiftData migration already completed -- skipping.")
            return
        }

        logger.info("Starting JSON -> SwiftData migration...")

        do {
            let context = ModelContext(container)

            // ── 1. Migrate Sleep Episodes ──────────────────────────────
            let episodes = store.sleepEpisodes
            for episode in episodes {
                context.insert(SDSleepEpisode(from: episode))
            }

            // ── 2. Migrate Circadian Events ────────────────────────────
            let events = store.events
            for event in events {
                context.insert(SDCircadianEvent(from: event))
            }

            // ── 3. Migrate Prediction History ──────────────────────────
            let predictions = store.predictionHistory
            for prediction in predictions {
                context.insert(SDPredictionResult(from: prediction))
            }

            // ── 4. Migrate Chat History ────────────────────────────────
            let messages = store.chatHistory
            for message in messages {
                context.insert(SDCoachMessage(from: message))
            }

            // ── 5. Migrate Sleep Goal ──────────────────────────────────
            let goal = store.sleepGoal
            context.insert(SDUserGoal(from: goal))

            // ── 6. Save ────────────────────────────────────────────────
            try context.save()
            logger.info("SwiftData migration: inserted \(episodes.count) episodes, \(events.count) events, \(predictions.count) predictions, \(messages.count) messages, 1 goal.")

            // ── 7. Verify ──────────────────────────────────────────────
            try verify(
                context: context,
                expectedEpisodes: episodes,
                expectedEvents: events,
                expectedPredictions: predictions,
                expectedMessages: messages
            )

            // ── 8. Mark complete ───────────────────────────────────────
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("SwiftData migration completed and verified successfully.")

        } catch {
            // Migration failed -- do NOT mark complete.
            // JSON data in UserDefaults is left intact so we can retry on next launch.
            logger.error("SwiftData migration failed: \(error.localizedDescription). Will retry next launch.")
        }
    }

    // MARK: - Verification

    /// Verify migrated record counts and spot-check first/last episode timestamps.
    private static func verify(
        context: ModelContext,
        expectedEpisodes: [SleepEpisode],
        expectedEvents: [CircadianEvent],
        expectedPredictions: [PredictionResult],
        expectedMessages: [ChatMessage]
    ) throws {
        // Count verification
        let episodeCount = try context.fetchCount(FetchDescriptor<SDSleepEpisode>())
        let eventCount = try context.fetchCount(FetchDescriptor<SDCircadianEvent>())
        let predictionCount = try context.fetchCount(FetchDescriptor<SDPredictionResult>())
        let messageCount = try context.fetchCount(FetchDescriptor<SDCoachMessage>())
        let goalCount = try context.fetchCount(FetchDescriptor<SDUserGoal>())

        guard episodeCount >= expectedEpisodes.count else {
            throw MigrationError.countMismatch(
                entity: "SDSleepEpisode",
                expected: expectedEpisodes.count,
                actual: episodeCount
            )
        }
        guard eventCount >= expectedEvents.count else {
            throw MigrationError.countMismatch(
                entity: "SDCircadianEvent",
                expected: expectedEvents.count,
                actual: eventCount
            )
        }
        guard predictionCount >= expectedPredictions.count else {
            throw MigrationError.countMismatch(
                entity: "SDPredictionResult",
                expected: expectedPredictions.count,
                actual: predictionCount
            )
        }
        guard messageCount >= expectedMessages.count else {
            throw MigrationError.countMismatch(
                entity: "SDCoachMessage",
                expected: expectedMessages.count,
                actual: messageCount
            )
        }
        guard goalCount >= 1 else {
            throw MigrationError.countMismatch(
                entity: "SDUserGoal",
                expected: 1,
                actual: goalCount
            )
        }

        // Spot-check: first and last episode start/end values
        if let firstSource = expectedEpisodes.first,
           let lastSource = expectedEpisodes.last {

            var firstDescriptor = FetchDescriptor<SDSleepEpisode>(
                sortBy: [SortDescriptor(\.start, order: .forward)]
            )
            firstDescriptor.fetchLimit = 1

            var lastDescriptor = FetchDescriptor<SDSleepEpisode>(
                sortBy: [SortDescriptor(\.start, order: .reverse)]
            )
            lastDescriptor.fetchLimit = 1

            let firstMigrated = try context.fetch(firstDescriptor).first
            let lastMigrated = try context.fetch(lastDescriptor).first

            if let first = firstMigrated {
                guard abs(first.start - firstSource.start) < 0.001,
                      abs(first.end - firstSource.end) < 0.001 else {
                    throw MigrationError.spotCheckFailed(
                        detail: "First episode mismatch: expected start=\(firstSource.start) end=\(firstSource.end), got start=\(first.start) end=\(first.end)"
                    )
                }
            }

            if let last = lastMigrated {
                guard abs(last.start - lastSource.start) < 0.001,
                      abs(last.end - lastSource.end) < 0.001 else {
                    throw MigrationError.spotCheckFailed(
                        detail: "Last episode mismatch: expected start=\(lastSource.start) end=\(lastSource.end), got start=\(last.start) end=\(last.end)"
                    )
                }
            }
        }

        logger.info("Migration verification passed: \(episodeCount) episodes, \(eventCount) events, \(predictionCount) predictions, \(messageCount) messages, \(goalCount) goal(s).")
    }

    // MARK: - Errors

    enum MigrationError: LocalizedError {
        case countMismatch(entity: String, expected: Int, actual: Int)
        case spotCheckFailed(detail: String)

        var errorDescription: String? {
            switch self {
            case .countMismatch(let entity, let expected, let actual):
                return "Migration count mismatch for \(entity): expected \(expected), got \(actual)."
            case .spotCheckFailed(let detail):
                return "Migration spot-check failed: \(detail)"
            }
        }
    }
}
