import Foundation

/// Stateless conflict detection engine.
///
/// Compares sleep records against context blocks (work, study, commute, etc.)
/// and produces `ScheduleConflict` items when misalignment is detected.
///
/// Follows the same pattern as `NapOptimizer` and `DisorderDetection`:
/// a public enum with static methods, no mutable state, fully testable.
///
/// Three types of conflict are detected:
/// 1. **sleepOverlapsBlock** — sleep physically overlaps with a scheduled block.
/// 2. **sleepTooCloseToBlockStart** — wake-up is less than `bufferMinutes` before a block starts.
/// 3. **daytimeSleepConsumesWindow** — significant daytime sleep (≥ 45 min) falls within a block.
public enum ScheduleConflictDetector {

    // MARK: - Thresholds

    /// Default minimum buffer between wake-up and block start (minutes).
    public static let defaultBufferMinutes: Double = 60.0

    /// Minimum overlap to report (minutes). Avoids noise from rounding or HealthKit granularity.
    private static let overlapNoiseFloor: Double = 15.0

    /// Minimum daytime sleep within a block window to flag (minutes).
    /// 20-min power naps are fine; 45+ min siestas during work are flagged.
    private static let daytimeSleepThreshold: Double = 45.0

    /// Extended buffer for high-cognitive-demand blocks (minutes).
    /// Based on sleep inertia research: full cognitive dissipation can take 2–4 h,
    /// and shift-work guidelines recommend avoiding risk tasks within 90 min of waking.
    public static let highRiskBufferMinutes: Double = 90.0

    // MARK: - Public API

    /// Detect all conflicts between sleep records and context blocks.
    ///
    /// - Parameters:
    ///   - records: Sleep records to check (typically the full computed set).
    ///   - blocks: Active context blocks defined by the user or imported from calendar.
    ///   - bufferMinutes: Minimum acceptable gap between wake-up and block start.
    /// - Returns: Array of detected conflicts, sorted by day (ascending).
    public static func detect(
        records: [SleepRecord],
        blocks: [ContextBlock],
        bufferMinutes: Double = defaultBufferMinutes
    ) -> [ScheduleConflict] {
        let activeBlocks = blocks.filter(\.isEnabled)
        guard !activeBlocks.isEmpty, !records.isEmpty else { return [] }

        var conflicts: [ScheduleConflict] = []

        for record in records {
            for block in activeBlocks {
                guard block.isActive(on: record.date) else { continue }

                // 1. Direct overlap: sleep window intersects block window
                let overlapMins = circularOverlapMinutes(
                    sleepStart: record.bedtimeHour,
                    sleepEnd: record.wakeupHour,
                    blockStart: block.startHour,
                    blockEnd: block.endHour
                )

                if overlapMins > overlapNoiseFloor {
                    conflicts.append(ScheduleConflict(
                        type: .sleepOverlapsBlock,
                        blockID: block.id,
                        blockType: block.type,
                        blockLabel: block.label,
                        day: record.day,
                        overlapMinutes: overlapMins,
                        sleepEndHour: record.wakeupHour,
                        blockStartHour: block.startHour
                    ))
                    // Don't double-flag overlap + too-close for the same block/day.
                    continue
                }

                // 2. Too close: wake ends < buffer before block starts
                //    Two-tier severity:
                //    - alert:    gap < bufferMinutes (default 60 min)
                //    - highRisk: gap < 90 min AND block is high-cognitive-demand
                let gapMins = circularGapMinutes(from: record.wakeupHour, to: block.startHour)

                let effectiveBuffer = block.type.isHighCognitiveDemand
                    ? max(bufferMinutes, highRiskBufferMinutes)
                    : bufferMinutes

                if gapMins >= 0 && gapMins < effectiveBuffer {
                    let severity: BufferSeverity?
                    if gapMins < bufferMinutes {
                        severity = .alert
                    } else if block.type.isHighCognitiveDemand && gapMins < highRiskBufferMinutes {
                        severity = .highRisk
                    } else {
                        severity = nil
                    }

                    conflicts.append(ScheduleConflict(
                        type: .sleepTooCloseToBlockStart,
                        blockID: block.id,
                        blockType: block.type,
                        blockLabel: block.label,
                        day: record.day,
                        overlapMinutes: effectiveBuffer - gapMins,
                        sleepEndHour: record.wakeupHour,
                        blockStartHour: block.startHour,
                        bufferSeverity: severity
                    ))
                }

                // 3. Daytime sleep consuming operational window
                let daytimeMins = daytimeSleepInWindow(
                    hourlyActivity: record.hourlyActivity,
                    windowStart: block.startHour,
                    windowEnd: block.endHour
                )

                if daytimeMins >= daytimeSleepThreshold {
                    conflicts.append(ScheduleConflict(
                        type: .daytimeSleepConsumesWindow,
                        blockID: block.id,
                        blockType: block.type,
                        blockLabel: block.label,
                        day: record.day,
                        overlapMinutes: daytimeMins,
                        sleepEndHour: record.wakeupHour,
                        blockStartHour: block.startHour
                    ))
                }
            }
        }

        return conflicts.sorted { $0.day < $1.day }
    }

    // MARK: - Circular Time Math

    /// Calculate minutes of overlap between two circular 24-hour windows.
    ///
    /// Handles overnight windows correctly (e.g. sleep 23:00–07:00, work 22:00–06:00).
    /// Both windows are expanded to linear ranges, overlapped, and the result clamped.
    ///
    /// - Parameters:
    ///   - sleepStart: Bedtime clock hour (0–24).
    ///   - sleepEnd: Wake-up clock hour (0–24).
    ///   - blockStart: Block start clock hour (0–24).
    ///   - blockEnd: Block end clock hour (0–24).
    /// - Returns: Overlap in minutes (≥ 0).
    static func circularOverlapMinutes(
        sleepStart: Double, sleepEnd: Double,
        blockStart: Double, blockEnd: Double
    ) -> Double {
        // Convert circular windows to linear ranges.
        // If end < start, it wraps past midnight — extend end by 24.
        let sStart = sleepStart
        let sEnd   = sleepEnd < sleepStart ? sleepEnd + 24.0 : sleepEnd

        let bStart = blockStart
        let bEnd   = blockEnd < blockStart ? blockEnd + 24.0 : blockEnd

        // Try overlap in the original alignment and shifted by 24h to catch wrapping.
        let overlap1 = overlapLinear(s0: sStart, s1: sEnd, b0: bStart, b1: bEnd)
        let overlap2 = overlapLinear(s0: sStart + 24, s1: sEnd + 24, b0: bStart, b1: bEnd)
        let overlap3 = overlapLinear(s0: sStart, s1: sEnd, b0: bStart + 24, b1: bEnd + 24)

        return max(overlap1, max(overlap2, overlap3))
    }

    /// Linear overlap between two intervals [s0,s1] and [b0,b1], in minutes.
    private static func overlapLinear(s0: Double, s1: Double, b0: Double, b1: Double) -> Double {
        let start = max(s0, b0)
        let end   = min(s1, b1)
        return max(0, (end - start) * 60.0)
    }

    /// Gap in minutes from `from` (clock hour) to `to` (clock hour) going forward on a 24h clock.
    ///
    /// - Returns: Positive if `to` is after `from` (forward gap), accounting for midnight wrap.
    ///   Always in range [0, 1440).
    static func circularGapMinutes(from: Double, to: Double) -> Double {
        var gap = (to - from) * 60.0
        if gap < 0 { gap += 1440.0 }
        return gap
    }

    /// Estimate minutes of sleep within a block's clock-hour window using hourlyActivity.
    ///
    /// hourlyActivity has 24 entries (0–23), each with an activity value 0.0 (asleep) to 1.0 (awake).
    /// Hours with activity < 0.3 are considered asleep.
    ///
    /// Handles overnight block windows (e.g. 22:00–06:00) with circular indexing.
    static func daytimeSleepInWindow(
        hourlyActivity: [HourlyActivity],
        windowStart: Double,
        windowEnd: Double
    ) -> Double {
        guard hourlyActivity.count == 24 else { return 0 }

        let startHour = Int(windowStart) % 24
        let endHour   = Int(windowEnd) % 24
        var sleepMinutes: Double = 0

        // Build list of hours in the window
        var hours: [Int] = []
        if startHour <= endHour {
            // Normal window: e.g. 09-17
            for h in startHour..<endHour {
                hours.append(h)
            }
        } else {
            // Overnight window: e.g. 22-06
            for h in startHour..<24 {
                hours.append(h)
            }
            for h in 0..<endHour {
                hours.append(h)
            }
        }

        for h in hours {
            let activity = hourlyActivity[h].activity
            if activity < 0.3 {
                // Mostly asleep during this hour → count as 60 min of sleep
                sleepMinutes += 60.0
            } else if activity < 0.5 {
                // Partially asleep → count proportionally
                sleepMinutes += (1.0 - activity) * 60.0
            }
        }

        return sleepMinutes
    }
}
