import Foundation

/// A single, human-readable "what matters this week" headline derived
/// from the aggregate stats. The rest of AnalysisTab can surface other
/// data, but the insight card shows exactly one of these — the first
/// rule below (in priority order) that clears its threshold wins.
///
/// Priority:
///   1. Social jet lag ≥ 1h
///   2. Weekend drift (weekend bedtime significantly later than weekdays)
///   3. Consistency dropped vs previous week by ≥ 10 points
///   4. Duration down ≥ 0.5h vs previous window
///   5. (Positive) Consistency ≥ 75 and SRI ≥ 75 → "good streak"
public struct WeeklyInsight: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case socialJetlag
        case weekendDrift
        case consistencyDrop
        case durationLoss
        case goodStreak
    }

    public let kind: Kind
    /// Short uppercase tag ("INSIGHT CLAVE", "BIEN HECHO").
    public let kickerKey: String
    /// Primary one-liner. Contains %@ placeholders filled by `headlineArgs`.
    public let headlineKey: String
    public let headlineArgs: [String]
    /// Secondary context. Optional — some insights don't have one.
    public let supportingKey: String?
    public let supportingArgs: [String]

    public init(kind: Kind,
                kickerKey: String,
                headlineKey: String,
                headlineArgs: [String] = [],
                supportingKey: String? = nil,
                supportingArgs: [String] = []) {
        self.kind = kind
        self.kickerKey = kickerKey
        self.headlineKey = headlineKey
        self.headlineArgs = headlineArgs
        self.supportingKey = supportingKey
        self.supportingArgs = supportingArgs
    }
}

public enum WeeklyInsightEngine {

    /// Derive the highest-priority insight for `records` (the last 7
    /// nights by convention) using stats already computed by the engine.
    ///
    /// Returns nil if there is not enough data (<3 nights) OR no rule
    /// clears its threshold.
    public static func generate(
        records: [SleepRecord],
        stats: SleepStats,
        consistency: SpiralConsistencyScore?
    ) -> WeeklyInsight? {
        guard records.count >= 3 else { return nil }

        // 1. Social jet lag (minutes → hours with 1-decimal formatting).
        if stats.socialJetlag >= 60 {
            let hours = stats.socialJetlag / 60.0
            return WeeklyInsight(
                kind: .socialJetlag,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.socialJetlag",
                headlineArgs: [String(format: "%.1fh", hours)],
                supportingKey: "analysis.insight.socialJetlagConsequence")
        }

        // 2. Weekend drift: avg weekend bedtime later than weekday by ≥ 1h.
        let weekdayBedtimes = records.filter { !$0.isWeekend }.map { $0.bedtimeHour }
        let weekendBedtimes = records.filter { $0.isWeekend }.map { $0.bedtimeHour }
        if weekdayBedtimes.count >= 2, weekendBedtimes.count >= 1 {
            let weekdayMean = circularMeanHour(weekdayBedtimes)
            let weekendMean = circularMeanHour(weekendBedtimes)
            let delta = hoursLater(weekendMean, than: weekdayMean)
            if delta >= 1.0 {
                return WeeklyInsight(
                    kind: .weekendDrift,
                    kickerKey: "analysis.insight.kicker",
                    headlineKey: "analysis.insight.weekendDrift",
                    headlineArgs: [String(format: "%.1fh", delta)],
                    supportingKey: "analysis.insight.weekendDriftConsequence")
            }
        }

        // 3. Consistency dropped ≥ 10 points vs previous week.
        if let c = consistency, let delta = c.deltaVsPreviousWeek, delta <= -10 {
            return WeeklyInsight(
                kind: .consistencyDrop,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.consistencyDrop",
                headlineArgs: [String(format: "%d", Int(abs(delta)))],
                supportingKey: "analysis.insight.consistencyDropConsequence")
        }

        // 4. Mean sleep duration noticeably low (< 6.5h).
        if stats.meanSleepDuration > 0, stats.meanSleepDuration < 6.5 {
            let deficit = 7.5 - stats.meanSleepDuration
            return WeeklyInsight(
                kind: .durationLoss,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.durationLoss",
                headlineArgs: [String(format: "%.1fh", stats.meanSleepDuration),
                               String(format: "%.1fh", deficit)])
        }

        // 5. Positive case: score ≥ 75 and SRI ≥ 75.
        if let c = consistency, c.score >= 75, stats.sri >= 75 {
            return WeeklyInsight(
                kind: .goodStreak,
                kickerKey: "analysis.insight.goodKicker",
                headlineKey: "analysis.insight.goodStreak",
                headlineArgs: [String(format: "%d", c.score)])
        }

        return nil
    }

    // MARK: - Helpers

    /// Circular mean for hours-of-day (0..24). Preserves the fact that
    /// 23h and 1h are 2 hours apart, not 22.
    private static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let radians = hours.map { $0 / 24.0 * 2 * .pi }
        let sinMean = radians.map(sin).reduce(0, +) / Double(hours.count)
        let cosMean = radians.map(cos).reduce(0, +) / Double(hours.count)
        var angle = atan2(sinMean, cosMean)
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi) * 24.0
    }

    /// Smallest non-negative delta in hours such that
    /// `shifted = reference + delta` (mod 24) equals `later`.
    private static func hoursLater(_ later: Double, than reference: Double) -> Double {
        var delta = later - reference
        while delta < 0 { delta += 24 }
        while delta >= 24 { delta -= 24 }
        // If the result is > 12 the other direction is shorter — treat
        // that as an "earlier" shift (no drift) by returning 0.
        return delta > 12 ? 0 : delta
    }
}
