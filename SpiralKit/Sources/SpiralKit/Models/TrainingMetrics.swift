import Foundation

/// Metrics captured during a single on-device model retraining run.
///
/// The validation split (80/20) lets us detect overfitting: if the
/// post-training MAE on the held-out set is worse than the pre-training
/// MAE, the update is rejected and the personalised model is rolled back.
public struct TrainingMetrics: Codable, Sendable {
    /// When the training run completed.
    public var date: Date
    /// Mean absolute error on the validation set BEFORE training (hours).
    public var preMae: Double
    /// Mean absolute error on the validation set AFTER training (hours).
    public var postMae: Double
    /// Number of samples used for training (≈ 80%).
    public var trainCount: Int
    /// Number of samples held out for validation (≈ 20%).
    public var validationCount: Int
    /// Whether the updated model was accepted (postMae < preMae).
    public var accepted: Bool

    public init(
        date: Date,
        preMae: Double,
        postMae: Double,
        trainCount: Int,
        validationCount: Int,
        accepted: Bool
    ) {
        self.date = date
        self.preMae = preMae
        self.postMae = postMae
        self.trainCount = trainCount
        self.validationCount = validationCount
        self.accepted = accepted
    }
}
