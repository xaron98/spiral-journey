import Foundation

/// A daily snapshot of detected schedule conflicts.
///
/// Captured each time `ScheduleConflictDetector.detect()` runs, these snapshots
/// accumulate over time to enable trend analysis: is the user's sleep–obligation
/// alignment improving, worsening, or stable?
///
/// The snapshot aggregates counts by conflict type and a mean buffer metric,
/// keeping each entry lightweight (~100 bytes JSON) for persistence in UserDefaults
/// and Watch sync within the 65 KB application-context budget.
///
/// Designed for 90-day rolling retention — older snapshots are trimmed on save.
public struct ConflictSnapshot: Codable, Sendable, Identifiable, Equatable {

    /// Unique identifier.
    public var id: UUID

    /// The calendar date this snapshot represents (start of day, UTC).
    public var date: Date

    /// Total number of conflicts detected on this date.
    public var totalConflicts: Int

    /// Number of `.sleepOverlapsBlock` conflicts.
    public var overlapCount: Int

    /// Number of `.sleepTooCloseToBlockStart` conflicts.
    public var bufferAlertCount: Int

    /// Number of `.daytimeSleepConsumesWindow` conflicts.
    public var daytimeSleepCount: Int

    /// Average buffer (gap) in minutes between wake-up and block start across all records.
    /// Nil when no buffer measurements are available (e.g. only overlap conflicts).
    public var meanBufferMinutes: Double?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        totalConflicts: Int = 0,
        overlapCount: Int = 0,
        bufferAlertCount: Int = 0,
        daytimeSleepCount: Int = 0,
        meanBufferMinutes: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.totalConflicts = totalConflicts
        self.overlapCount = overlapCount
        self.bufferAlertCount = bufferAlertCount
        self.daytimeSleepCount = daytimeSleepCount
        self.meanBufferMinutes = meanBufferMinutes
    }

    // MARK: - Factory

    /// Create a snapshot from a set of detected conflicts.
    ///
    /// - Parameters:
    ///   - conflicts: The conflicts detected for the current data window.
    ///   - date: The date to stamp on the snapshot (defaults to today).
    /// - Returns: A populated snapshot summarizing the conflicts.
    public static func from(
        conflicts: [ScheduleConflict],
        date: Date = Date()
    ) -> ConflictSnapshot {
        let overlap = conflicts.filter { $0.type == .sleepOverlapsBlock }.count
        let buffer  = conflicts.filter { $0.type == .sleepTooCloseToBlockStart }.count
        let daytime = conflicts.filter { $0.type == .daytimeSleepConsumesWindow }.count

        // Mean buffer: for buffer-type conflicts, the overlapMinutes field stores
        // how many minutes short of the buffer the gap was. We can derive approximate
        // actual gap as (defaultBuffer - shortfall). For overlap-type conflicts,
        // the gap is effectively 0 or negative.
        let bufferConflicts = conflicts.filter { $0.type == .sleepTooCloseToBlockStart }
        let meanBuf: Double? = bufferConflicts.isEmpty ? nil : {
            let gaps = bufferConflicts.map { ScheduleConflictDetector.defaultBufferMinutes - $0.overlapMinutes }
            return gaps.reduce(0, +) / Double(gaps.count)
        }()

        return ConflictSnapshot(
            date: Calendar.current.startOfDay(for: date),
            totalConflicts: conflicts.count,
            overlapCount: overlap,
            bufferAlertCount: buffer,
            daytimeSleepCount: daytime,
            meanBufferMinutes: meanBuf
        )
    }
}
