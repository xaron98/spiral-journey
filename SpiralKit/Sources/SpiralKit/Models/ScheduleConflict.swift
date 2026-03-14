import Foundation

// MARK: - Buffer Severity

/// Two-tier buffer severity based on sleep inertia research.
///
/// Sleep inertia (cognitive impairment on waking) typically lasts 15–30 min
/// but can follow a longer dissipation curve of 2–4 h. For high-cognitive-demand
/// tasks (work, study, commute, focus), a larger buffer is warranted.
///
/// References:
///   - Shift-work guidelines describe 15–30 min typical inertia, up to 2 h.
///   - Evidence supports personalizing the buffer by user and task type.
public enum BufferSeverity: String, Codable, Sendable {
    /// Buffer < 60 min — standard alert for any block type.
    case alert
    /// Buffer < 90 min for high-cognitive-demand blocks — extended risk zone.
    case highRisk
}

// MARK: - Schedule Conflict Type

/// Type of conflict between a sleep session and a context block.
public enum ScheduleConflictType: String, Codable, Sendable {
    /// Sleep episode physically overlaps with the context block window.
    case sleepOverlapsBlock

    /// Wake-up time is too close to the block's start (less than the configured buffer).
    case sleepTooCloseToBlockStart

    /// Significant daytime sleep (siesta ≥ 45 min) falls within the block's active window.
    case daytimeSleepConsumesWindow
}

// MARK: - Schedule Conflict

/// A detected conflict between sleep data and a context block.
///
/// Produced by `ScheduleConflictDetector.detect()`. The coach engine and UI consume these
/// to provide actionable feedback about sleep–obligation misalignment.
///
/// Design: The conflict stores denormalized block metadata (type, label, startHour)
/// so it can be displayed on Apple Watch without needing the full ContextBlock array.
public struct ScheduleConflict: Codable, Identifiable, Sendable, Equatable {

    /// Unique identifier.
    public var id: UUID

    /// What kind of conflict was detected.
    public var type: ScheduleConflictType

    /// ID of the related `ContextBlock`.
    public var blockID: UUID

    /// Denormalized block type for display without lookup.
    public var blockType: ContextBlockType

    /// Denormalized block label for display without lookup.
    public var blockLabel: String

    /// Day index in the record set (0-based).
    public var day: Int

    /// Magnitude of the conflict:
    /// - For `.sleepOverlapsBlock`: minutes of overlap.
    /// - For `.sleepTooCloseToBlockStart`: how many minutes short of the buffer.
    /// - For `.daytimeSleepConsumesWindow`: minutes of daytime sleep within the block.
    public var overlapMinutes: Double

    /// Clock hour when sleep ended on this day.
    public var sleepEndHour: Double

    /// Clock hour when the context block starts.
    public var blockStartHour: Double

    /// For `.sleepTooCloseToBlockStart` conflicts: severity level based on gap size
    /// and block cognitive demand. Nil for non-buffer conflicts.
    public var bufferSeverity: BufferSeverity?

    public init(
        id: UUID = UUID(),
        type: ScheduleConflictType,
        blockID: UUID,
        blockType: ContextBlockType,
        blockLabel: String,
        day: Int,
        overlapMinutes: Double,
        sleepEndHour: Double,
        blockStartHour: Double,
        bufferSeverity: BufferSeverity? = nil
    ) {
        self.id = id
        self.type = type
        self.blockID = blockID
        self.blockType = blockType
        self.blockLabel = blockLabel
        self.day = day
        self.overlapMinutes = overlapMinutes
        self.sleepEndHour = sleepEndHour
        self.blockStartHour = blockStartHour
        self.bufferSeverity = bufferSeverity
    }
}
