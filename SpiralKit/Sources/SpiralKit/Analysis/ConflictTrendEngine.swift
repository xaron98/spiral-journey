import Foundation

/// Analyzes conflict snapshots over time to detect trends.
///
/// Compares the current week's conflict counts against the previous week's
/// to determine if the user's sleep–obligation alignment is improving, worsening,
/// or stable. Requires at least 7 snapshots (one week) for meaningful analysis.
///
/// Follows the same stateless enum pattern as other SpiralKit engines
/// (`NapOptimizer`, `ScheduleConflictDetector`, `SleepinessRiskEngine`).
public enum ConflictTrendEngine {

    // MARK: - Types

    /// Direction of the conflict trend.
    public enum TrendDirection: String, Codable, Sendable {
        /// Conflicts decreased week-over-week.
        case improving
        /// Conflicts increased week-over-week.
        case worsening
        /// Conflicts remained roughly the same (delta ≤ 1).
        case stable
    }

    /// Result of conflict trend analysis.
    public struct ConflictTrend: Codable, Sendable {
        /// Overall direction of the trend.
        public let direction: TrendDirection

        /// Change in total conflicts: current week − previous week.
        /// Negative means improvement.
        public let weekOverWeekDelta: Int

        /// Total conflicts in the most recent 7-day window.
        public let currentWeekConflicts: Int

        /// Total conflicts in the 7-day window before the current one.
        public let previousWeekConflicts: Int

        /// Mean buffer minutes in the current week (nil if no buffer data).
        public let currentMeanBuffer: Double?

        /// Mean buffer minutes in the previous week (nil if no buffer data).
        public let previousMeanBuffer: Double?

        public init(
            direction: TrendDirection,
            weekOverWeekDelta: Int,
            currentWeekConflicts: Int,
            previousWeekConflicts: Int,
            currentMeanBuffer: Double? = nil,
            previousMeanBuffer: Double? = nil
        ) {
            self.direction = direction
            self.weekOverWeekDelta = weekOverWeekDelta
            self.currentWeekConflicts = currentWeekConflicts
            self.previousWeekConflicts = previousWeekConflicts
            self.currentMeanBuffer = currentMeanBuffer
            self.previousMeanBuffer = previousMeanBuffer
        }
    }

    // MARK: - Thresholds

    /// Minimum number of snapshots needed for trend analysis.
    /// Less than 7 means we don't have even one full week of data.
    public static let minimumSnapshots = 7

    /// Delta threshold: changes within this range are considered stable.
    /// A single conflict difference day-to-day can be noise.
    private static let stabilityThreshold = 1

    // MARK: - Public API

    /// Analyze conflict trend from a history of daily snapshots.
    ///
    /// Splits the snapshots into a "current week" (most recent 7 days) and
    /// "previous week" (the 7 days before that). If fewer than 7 snapshots
    /// exist, returns nil.
    ///
    /// - Parameter snapshots: Daily conflict snapshots, in any order.
    /// - Returns: A `ConflictTrend` describing the direction, or nil if insufficient data.
    public static func analyze(snapshots: [ConflictSnapshot]) -> ConflictTrend? {
        guard snapshots.count >= minimumSnapshots else { return nil }

        // Sort by date ascending
        let sorted = snapshots.sorted { $0.date < $1.date }

        // Split into current week (last 7) and previous week (7 before those)
        let currentWeek = Array(sorted.suffix(7))
        let remaining = sorted.dropLast(7)

        // Previous week: take up to 7 from what's left
        let previousWeek = Array(remaining.suffix(min(7, remaining.count)))

        // Sum conflicts for each period
        let currentTotal = currentWeek.reduce(0) { $0 + $1.totalConflicts }
        let previousTotal = previousWeek.reduce(0) { $0 + $1.totalConflicts }

        // Mean buffer for each period
        let currentBuffers = currentWeek.compactMap(\.meanBufferMinutes)
        let previousBuffers = previousWeek.compactMap(\.meanBufferMinutes)

        let currentMeanBuf = currentBuffers.isEmpty ? nil : currentBuffers.reduce(0, +) / Double(currentBuffers.count)
        let previousMeanBuf = previousBuffers.isEmpty ? nil : previousBuffers.reduce(0, +) / Double(previousBuffers.count)

        // Determine direction using daily averages to handle asymmetric week lengths
        // (e.g., 8-13 snapshots: current week = 7 days, previous = 1-6 days).
        let delta = currentTotal - previousTotal
        let direction: TrendDirection
        if previousWeek.isEmpty {
            // Only one week of data — can't compare, report stable
            direction = .stable
        } else {
            let currentDailyAvg = Double(currentTotal) / Double(currentWeek.count)
            let previousDailyAvg = Double(previousTotal) / Double(previousWeek.count)
            let avgDelta = currentDailyAvg - previousDailyAvg
            // Threshold: a change of less than ~0.15 conflicts/day is noise
            // (equivalent to ~1 conflict/week difference)
            let dailyStabilityThreshold = Double(stabilityThreshold) / 7.0
            if avgDelta <= -dailyStabilityThreshold - 0.01 {
                direction = .improving
            } else if avgDelta >= dailyStabilityThreshold + 0.01 {
                direction = .worsening
            } else {
                direction = .stable
            }
        }

        return ConflictTrend(
            direction: direction,
            weekOverWeekDelta: delta,
            currentWeekConflicts: currentTotal,
            previousWeekConflicts: previousTotal,
            currentMeanBuffer: currentMeanBuf,
            previousMeanBuffer: previousMeanBuf
        )
    }

    /// Trim a snapshot history to a maximum number of days.
    ///
    /// Keeps the most recent snapshots and discards older ones.
    /// Deduplicates by date (keeps the latest snapshot for each calendar day).
    ///
    /// - Parameters:
    ///   - snapshots: The full history.
    ///   - maxDays: Maximum days to retain (default 90).
    /// - Returns: Trimmed array sorted by date ascending.
    public static func trimmed(
        _ snapshots: [ConflictSnapshot],
        maxDays: Int = 90
    ) -> [ConflictSnapshot] {
        // Deduplicate: keep the last snapshot per calendar day
        var byDay: [String: ConflictSnapshot] = [:]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        for snap in snapshots {
            let key = fmt.string(from: snap.date)
            byDay[key] = snap  // last write wins
        }

        // Sort by date ascending, trim to maxDays
        let sorted = byDay.values.sorted { $0.date < $1.date }
        return Array(sorted.suffix(maxDays))
    }
}
