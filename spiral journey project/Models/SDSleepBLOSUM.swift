import Foundation
import SwiftData

/// Persisted learned SleepBLOSUM feature weights.
///
/// Stored separately from the snapshot so that intermediate-tier computations
/// can reuse previously learned weights without decoding the full profile.
@Model
final class SDSleepBLOSUM {

    // MARK: Persisted Properties

    /// When these weights were last updated.
    var updatedAt: Date

    /// JSON-encoded `[Double]` — the 16 per-feature importance weights.
    var weightsJSON: String

    // MARK: Init

    init(updatedAt: Date, weightsJSON: String) {
        self.updatedAt = updatedAt
        self.weightsJSON = weightsJSON
    }
}
