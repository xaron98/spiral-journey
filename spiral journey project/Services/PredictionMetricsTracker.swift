import Foundation
import SwiftData

// MARK: - PredictionMetricsTracker

/// Computes rolling prediction quality metrics from evaluated SDPredictionResult
/// records and persists a summary SDPredictionMetrics snapshot.
@MainActor
enum PredictionMetricsTracker {

    // MARK: Types

    enum Trend: String {
        case improving, stable, worsening
    }

    struct Result {
        let mae: Double      // hours
        let accuracy: Double  // 0–100
        let trend: Trend
    }

    // MARK: Public

    /// Evaluate recent predictions, insert an SDPredictionMetrics record, and
    /// return the computed metrics.  Returns `nil` when there is insufficient data.
    @discardableResult
    static func evaluate(context: ModelContext) -> Result? {
        // ① Fetch last 30 evaluated predictions (actualBedtimeHour != nil).
        var descriptor = FetchDescriptor<SDPredictionResult>(
            predicate: #Predicate { $0.actualBedtimeHour != nil },
            sortBy: [SortDescriptor(\.targetDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30

        guard let results = try? context.fetch(descriptor), !results.isEmpty else {
            return nil
        }

        // ② Filter to last 14 days.
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = results.filter { $0.targetDate >= cutoff }
        guard !recent.isEmpty else { return nil }

        // ③ Compute MAE (in hours) and accuracy.
        let errors: [Double] = recent.compactMap { r in
            guard let errMin = r.errorBedtimeMinutes else { return nil }
            return abs(errMin) / 60.0
        }
        guard !errors.isEmpty else { return nil }

        let mae = errors.reduce(0, +) / Double(errors.count)
        let withinThreshold = errors.filter { $0 <= 0.5 }.count
        let accuracy = Double(withinThreshold) / Double(errors.count) * 100.0

        // ④ Trend: split into halves and compare MAE.
        let trend: Trend
        if errors.count >= 4 {
            let mid = errors.count / 2
            // `recent` is sorted descending ⇒ first half = newer, second half = older.
            let newerMAE = errors[0..<mid].reduce(0, +) / Double(mid)
            let olderMAE = errors[mid...].reduce(0, +) / Double(errors.count - mid)
            let delta = newerMAE - olderMAE
            if delta < -0.05 {
                trend = .improving
            } else if delta > 0.05 {
                trend = .worsening
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }

        // ⑤ Persist an SDPredictionMetrics snapshot.
        let metrics = SDPredictionMetrics(
            mae: mae,
            accuracy: accuracy,
            sampleCount: errors.count
        )
        context.insert(metrics)
        try? context.save()

        return Result(mae: mae, accuracy: accuracy, trend: trend)
    }
}
