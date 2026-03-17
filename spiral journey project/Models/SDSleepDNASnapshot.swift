import Foundation
import SwiftData

/// Persisted snapshot of a computed SleepDNA profile.
///
/// The full `SleepDNAProfile` is stored as compressed JSON in external storage
/// to avoid bloating the main SwiftData store. Lightweight metadata (tier,
/// week count, timestamp) is kept inline for queries.
@Model
final class SDSleepDNASnapshot {

    // MARK: Persisted Properties

    /// When this profile was computed.
    var computedAt: Date

    /// Analysis tier as a raw string ("basic", "intermediate", "full").
    var tier: String

    /// Number of full weeks of data that were available.
    var dataWeeks: Int

    /// JSON-encoded `SleepDNAProfile`, stored externally to keep the database lean.
    @Attribute(.externalStorage) var profileJSON: Data?

    // MARK: Init

    init(computedAt: Date, tier: String, dataWeeks: Int, profileJSON: Data?) {
        self.computedAt = computedAt
        self.tier = tier
        self.dataWeeks = dataWeeks
        self.profileJSON = profileJSON
    }
}
