import Foundation
import SwiftData

// MARK: - SDTrainingMetrics

/// SwiftData model for tracking ML model retraining runs.
/// One row per training session, recording before/after MAE and whether
/// the retrained model was accepted.
@Model
final class SDTrainingMetrics {

    // MARK: Persisted Properties

    @Attribute(.unique) var trainingID: UUID
    /// When this training run occurred.
    var date: Date
    /// MAE before retraining (minutes).
    var preMae: Double
    /// MAE after retraining (minutes).
    var postMae: Double
    /// Number of samples used for training.
    var trainCount: Int
    /// Number of samples used for validation.
    var validationCount: Int
    /// Whether the retrained model was accepted (postMae < preMae).
    var accepted: Bool

    // MARK: Init

    init(
        trainingID: UUID = UUID(),
        date: Date = Date(),
        preMae: Double,
        postMae: Double,
        trainCount: Int,
        validationCount: Int,
        accepted: Bool
    ) {
        self.trainingID = trainingID
        self.date = date
        self.preMae = preMae
        self.postMae = postMae
        self.trainCount = trainCount
        self.validationCount = validationCount
        self.accepted = accepted
    }
}
