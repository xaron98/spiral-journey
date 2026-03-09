import Foundation

/// Data source for a sleep episode.
public enum DataSource: String, Codable, Sendable {
    case healthKit = "healthKit"
    case manual    = "manual"
}

/// A continuous sleep episode recorded as absolute hours from day 0 00:00.
/// Example: { start: 23.5, end: 31.0 } = day 0 23:30 → day 1 07:00
public struct SleepEpisode: Codable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double          // absolute hours from epoch day 0
    public var end: Double
    public var source: DataSource
    public var healthKitSampleID: String?

    public var duration: Double { end - start }

    public init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        source: DataSource = .manual,
        healthKitSampleID: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        self.healthKitSampleID = healthKitSampleID
    }
}
