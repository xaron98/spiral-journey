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
    private static let sThreshold = 0.55
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
