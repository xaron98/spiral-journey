import Foundation
import SwiftData

// MARK: - DataRetentionService

/// Enforces data retention policies by trimming old or excessive records.
///
/// Policies:
/// - **Chat history:** keep last 100 SDCoachMessage, delete older.
/// - **Prediction metrics:** delete SDPredictionMetrics older than 90 days.
/// - **Training metrics:** delete SDTrainingMetrics older than 90 days.
/// - **Predictions:** keep ALL (valuable for ML training).
@MainActor
enum DataRetentionService {

    /// Run all retention policies against the given context.
    static func enforce(context: ModelContext) {
        trimChatHistory(context: context)
        trimPredictionMetrics(context: context)
        trimTrainingMetrics(context: context)
    }

    // MARK: - Private

    /// Keep only the most recent 100 coach messages.
    private static func trimChatHistory(context: ModelContext) {
        let keepCount = 100

        var descriptor = FetchDescriptor<SDCoachMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        // Fetch keepCount + 1 so we know if trimming is needed.
        descriptor.fetchLimit = keepCount + 1

        guard let messages = try? context.fetch(descriptor),
              messages.count > keepCount else { return }

        // There are more than `keepCount` messages. Fetch the oldest ones to delete.
        guard let cutoffDate = messages.last?.timestamp else { return }

        var oldDescriptor = FetchDescriptor<SDCoachMessage>(
            predicate: #Predicate { $0.timestamp < cutoffDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        oldDescriptor.fetchLimit = 500 // safety cap per run

        guard let oldMessages = try? context.fetch(oldDescriptor) else { return }
        for message in oldMessages {
            context.delete(message)
        }
        try? context.save()
    }

    /// Delete prediction metrics older than 90 days.
    private static func trimPredictionMetrics(context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return }

        var descriptor = FetchDescriptor<SDPredictionMetrics>(
            predicate: #Predicate { $0.date < cutoff }
        )
        descriptor.fetchLimit = 500

        guard let old = try? context.fetch(descriptor), !old.isEmpty else { return }
        for record in old {
            context.delete(record)
        }
        try? context.save()
    }

    /// Delete training metrics older than 90 days.
    private static func trimTrainingMetrics(context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return }

        var descriptor = FetchDescriptor<SDTrainingMetrics>(
            predicate: #Predicate { $0.date < cutoff }
        )
        descriptor.fetchLimit = 500

        guard let old = try? context.fetch(descriptor), !old.isEmpty else { return }
        for record in old {
            context.delete(record)
        }
        try? context.save()
    }
}
