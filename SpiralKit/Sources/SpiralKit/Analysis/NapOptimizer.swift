import Foundation

/// Nap recommendation engine based on Process S and circadian phase.
///
/// Uses continuous Process S to determine sleep pressure at potential nap times,
/// combined with circadian dip timing (~14:00 ± 1h) for optimal nap windows.
///
/// References:
///   - Milner & Cote (2009). Benefits of napping in healthy adults.
///   - Lovato & Lack (2010). The effects of napping on cognitive functioning.
public enum NapOptimizer {

    /// Reason for nap recommendation.
    public enum NapReason: String, Codable, Sendable {
        case highPressure    // S > threshold — general sleep pressure
        case circadianDip    // Coincides with post-lunch circadian dip
        case debtRecovery    // Multiple days of accumulated debt
        case contextAdjusted // Moved or shortened to avoid a context block
    }

    /// A nap recommendation with timing and rationale.
    public struct NapRecommendation: Sendable {
        /// Suggested start time (clock hour, 12.0–16.0 range).
        public let suggestedStart: Double
        /// Duration in minutes: 20 (power nap) or 90 (full cycle).
        public let duration: Int
        /// Process S value at the recommended time.
        public let sleepPressure: Double
        /// Why the nap is recommended.
        public let reason: NapReason
    }

    // MARK: - Thresholds

    /// Minimum S to recommend any nap.
    /// Aligned with SleepinessRiskEngine.moderateRiskThreshold (0.50)
    /// so that moderate sleepiness risk always yields a nap recommendation.
    private static let sThreshold = 0.50
    /// S above this → recommend 90-min full cycle instead of 20-min power nap.
    private static let sHighThreshold = 0.70
    /// Default nap window.
    private static let napWindowStart = 12.0
    private static let napWindowEnd = 16.0
    /// Circadian dip center (post-lunch).
    private static let circadianDipCenter = 14.0

    // MARK: - Public API

    /// Generate a nap recommendation based on recent sleep data.
    ///
    /// - Parameters:
    ///   - records: Recent sleep records (at least 1 day).
    ///   - wakeHour: Today's wake-up hour (clock time).
    ///   - chronotype: Optional chronotype for window adjustment.
    /// - Returns: A recommendation if a nap is beneficial, nil otherwise.
    public static func recommend(
        records: [SleepRecord],
        wakeHour: Double,
        chronotype: Chronotype? = nil
    ) -> NapRecommendation? {
        guard !records.isEmpty else { return nil }

        // Use continuous Process S to get current sleep pressure
        let points = TwoProcessModel.computeContinuous(records)
        guard !points.isEmpty else { return nil }

        // Adjust nap window based on chronotype
        let windowShift: Double
        switch chronotype {
        case .definiteMorning, .moderateMorning:
            windowShift = -1.0   // Earlier nap for morning types
        case .moderateEvening, .definiteEvening:
            windowShift = 1.0    // Later nap for evening types
        case .intermediate, .none:
            windowShift = 0.0
        }

        let windowStart = napWindowStart + windowShift
        let windowEnd = napWindowEnd + windowShift
        let dipCenter = circadianDipCenter + windowShift

        // Get S values during today's potential nap window (last day in records)
        let lastDay = records.count - 1
        let dayPoints = points.filter { $0.day == lastDay }

        // Find the hour in the nap window with highest S
        var bestHour: Int?
        var bestS: Double = 0

        for p in dayPoints {
            let hour = Double(p.hour)
            guard hour >= windowStart && hour <= windowEnd else { continue }
            if p.s > bestS {
                bestS = p.s
                bestHour = p.hour
            }
        }

        guard bestS >= sThreshold, let napHour = bestHour else { return nil }

        // Determine reason
        let reason: NapReason
        let distanceFromDip = abs(Double(napHour) - dipCenter)
        if distanceFromDip <= 1.0 {
            reason = .circadianDip
        } else if isMultiDayDebt(points: points, numDays: records.count) {
            reason = .debtRecovery
        } else {
            reason = .highPressure
        }

        // Duration: 20 min power nap vs 90 min full cycle
        let duration = bestS >= sHighThreshold ? 90 : 20

        return NapRecommendation(
            suggestedStart: Double(napHour),
            duration: duration,
            sleepPressure: bestS,
            reason: reason
        )
    }

    // MARK: - Context-Aware Recommendation

    /// Generate a nap recommendation that respects context blocks (work, study, etc.).
    ///
    /// Uses the base `recommend()` to compute the initial suggestion, then adjusts
    /// timing and duration to avoid conflicts with active context blocks on `date`.
    ///
    /// Adjustment strategy (per research recommendation):
    /// 1. If 90-min nap overlaps a block → try 20-min power nap at the same hour.
    /// 2. If still overlapping → shift nap to 30 min before the block starts.
    /// 3. If no valid slot fits in the nap window → return nil.
    ///
    /// - Parameters:
    ///   - records: Recent sleep records (at least 1 day).
    ///   - wakeHour: Today's wake-up hour (clock time).
    ///   - chronotype: Optional chronotype for window adjustment.
    ///   - contextBlocks: Active context blocks. Empty = behaves like base `recommend()`.
    ///   - weekday: Calendar weekday (1=Sunday, ..., 7=Saturday) to filter active blocks.
    ///     Deprecated — prefer the `date:` overload for correct one-off event handling.
    /// - Returns: A recommendation if a nap is beneficial and doesn't conflict, nil otherwise.
    public static func recommend(
        records: [SleepRecord],
        wakeHour: Double,
        chronotype: Chronotype? = nil,
        contextBlocks: [ContextBlock],
        weekday: Int
    ) -> NapRecommendation? {
        // Get base recommendation
        guard let base = recommend(records: records, wakeHour: wakeHour, chronotype: chronotype) else {
            return nil
        }

        // No blocks → return base unmodified
        let activeBlocks = contextBlocks.filter { $0.isEnabled && $0.isActive(weekday: weekday) }
        guard !activeBlocks.isEmpty else { return base }

        return adjustForBlocks(base: base, activeBlocks: activeBlocks, chronotype: chronotype)
    }

    /// Generate a nap recommendation that respects context blocks, using full date matching.
    ///
    /// This overload correctly restricts one-off calendar events to their specific date
    /// via `ContextBlock.isActive(on:)`.
    public static func recommend(
        records: [SleepRecord],
        wakeHour: Double,
        chronotype: Chronotype? = nil,
        contextBlocks: [ContextBlock],
        date: Date
    ) -> NapRecommendation? {
        guard let base = recommend(records: records, wakeHour: wakeHour, chronotype: chronotype) else {
            return nil
        }

        let activeBlocks = contextBlocks.filter { $0.isEnabled && $0.isActive(on: date) }
        guard !activeBlocks.isEmpty else { return base }

        return adjustForBlocks(base: base, activeBlocks: activeBlocks, chronotype: chronotype)
    }

    /// Shared logic: adjust a base nap recommendation to avoid context block conflicts.
    private static func adjustForBlocks(
        base: NapRecommendation,
        activeBlocks: [ContextBlock],
        chronotype: Chronotype?
    ) -> NapRecommendation? {

        // Check if base recommendation conflicts with any block
        if !napConflicts(start: base.suggestedStart, durationMin: base.duration, blocks: activeBlocks) {
            return base
        }

        // Strategy 1: If 90-min nap, try 20-min power nap at the same time
        if base.duration == 90 {
            let shortNap = NapRecommendation(
                suggestedStart: base.suggestedStart,
                duration: 20,
                sleepPressure: base.sleepPressure,
                reason: .contextAdjusted
            )
            if !napConflicts(start: shortNap.suggestedStart, durationMin: shortNap.duration, blocks: activeBlocks) {
                return shortNap
            }
        }

        // Strategy 2: Move nap to 30 min before the earliest conflicting block
        let windowShift: Double
        switch chronotype {
        case .definiteMorning, .moderateMorning: windowShift = -1.0
        case .moderateEvening, .definiteEvening:  windowShift = 1.0
        case .intermediate, .none:                windowShift = 0.0
        }
        let windowStart = napWindowStart + windowShift
        let windowEnd = napWindowEnd + windowShift

        for block in activeBlocks.sorted(by: { $0.startHour < $1.startHour }) {
            let candidate = block.startHour - 0.5  // 30 min before block
            guard candidate >= windowStart && candidate + Double(20) / 60.0 <= windowEnd else { continue }

            if !napConflicts(start: candidate, durationMin: 20, blocks: activeBlocks) {
                return NapRecommendation(
                    suggestedStart: candidate,
                    duration: 20,
                    sleepPressure: base.sleepPressure,
                    reason: .contextAdjusted
                )
            }
        }

        // No valid slot found
        return nil
    }

    /// Whether a nap at `start` with `durationMin` overlaps any of the given blocks.
    private static func napConflicts(start: Double, durationMin: Int, blocks: [ContextBlock]) -> Bool {
        let napEnd = start + Double(durationMin) / 60.0
        for block in blocks {
            let overlap = ScheduleConflictDetector.circularOverlapMinutes(
                sleepStart: start, sleepEnd: napEnd,
                blockStart: block.startHour, blockEnd: block.endHour
            )
            if overlap > 5.0 { return true }  // > 5 min noise floor
        }
        return false
    }

    // MARK: - Helpers

    /// Check if there's multi-day sleep debt accumulation.
    /// If S baseline at wake has been rising over the last 3+ days, it's debt.
    private static func isMultiDayDebt(points: [TwoProcessModel.TwoProcessPoint], numDays: Int) -> Bool {
        guard numDays >= 3 else { return false }

        // Get S at hour 8 (approximate wake stabilization) for last 3 days
        let recentDays = max(0, numDays - 3)..<numDays
        var morningS: [Double] = []

        for day in recentDays {
            if let p = points.first(where: { $0.day == day && $0.hour == 8 }) {
                morningS.append(p.s)
            }
        }

        guard morningS.count >= 3 else { return false }

        // Rising trend: each day's morning S is higher than previous
        return morningS[1] > morningS[0] && morningS[2] > morningS[1]
    }
}
