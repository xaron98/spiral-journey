import Foundation
import SwiftData

// MARK: - SDPredictionMetrics

/// SwiftData model for tracking prediction accuracy over time.
/// One row per evaluation date, summarising how well predictions matched actuals.
@Model
final class SDPredictionMetrics {

    // MARK: Persisted Properties

    var metricsID: UUID
    /// The date these metrics cover.
    var date: Date
    /// Mean Absolute Error in minutes.
    var mae: Double
    /// Accuracy percentage (0-100).
    var accuracy: Double
    /// Number of evaluated prediction-actual pairs.
    var sampleCount: Int

    // MARK: Init

    init(
        metricsID: UUID = UUID(),
        date: Date = Date(),
        mae: Double,
        accuracy: Double,
        sampleCount: Int
    ) {
        self.metricsID = metricsID
        self.date = date
        self.mae = mae
        self.accuracy = accuracy
        self.sampleCount = sampleCount
    }
}
