import Foundation
import SwiftData
import SpiralKit

// MARK: - SDSleepEpisode

/// SwiftData model mirroring SpiralKit.SleepEpisode with an added modifiedAt
/// field for change-tracking in WatchSyncBridge.
@Model
final class SDSleepEpisode {

    // MARK: Persisted Properties

    @Attribute(.unique) var episodeID: UUID
    var start: Double
    var end: Double
    /// Stored as DataSource.rawValue ("healthKit" | "manual").
    var source: String
    var healthKitSampleID: String?
    /// Stored as SleepPhase.rawValue ("deep" | "rem" | "light" | "awake"), nil for manual.
    var phase: String?
    /// Change-tracking timestamp for WatchSyncBridge.
    var modifiedAt: Date

    // MARK: Init

    init(
        episodeID: UUID = UUID(),
        start: Double,
        end: Double,
        source: String = DataSource.manual.rawValue,
        healthKitSampleID: String? = nil,
        phase: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.episodeID = episodeID
        self.start = start
        self.end = end
        self.source = source
        self.healthKitSampleID = healthKitSampleID
        self.phase = phase
        self.modifiedAt = modifiedAt
    }

    // MARK: Converters

    /// Create an SDSleepEpisode from a SpiralKit SleepEpisode.
    convenience init(from episode: SleepEpisode) {
        self.init(
            episodeID: episode.id,
            start: episode.start,
            end: episode.end,
            source: episode.source.rawValue,
            healthKitSampleID: episode.healthKitSampleID,
            phase: episode.phase?.rawValue,
            modifiedAt: Date()
        )
    }

    /// Convert back to a SpiralKit SleepEpisode.
    func toSleepEpisode() -> SleepEpisode {
        SleepEpisode(
            id: episodeID,
            start: start,
            end: end,
            source: DataSource(rawValue: source) ?? .manual,
            healthKitSampleID: healthKitSampleID,
            phase: phase.flatMap { SleepPhase(rawValue: $0) }
        )
    }
}
