import Foundation

/// Builds a `PredictionInput` feature vector from existing app data.
///
/// Stateless enum following the convention of other SpiralKit analysis engines.
/// All heavy calculations delegate to existing models and engines.
public enum PredictionFeatureBuilder {

    /// Build a feature vector for sleep prediction.
    ///
    /// - Parameters:
    ///   - records: Recent sleep records (ideally sorted by day ascending)
    ///   - events: All circadian events
    ///   - consistency: Current consistency score (nil if not computed)
    ///   - chronotypeResult: User's chronotype (nil if not assessed)
    ///   - goalDuration: Target sleep duration in hours
    ///   - currentAbsHour: Current absolute hour on the spiral timeline
    ///   - period: Spiral period (usually 24)
    /// - Returns: A fully populated `PredictionInput`, or nil if no records.
    public static func build(
        records: [SleepRecord],
        events: [CircadianEvent],
        consistency: SpiralConsistencyScore?,
        chronotypeResult: ChronotypeResult?,
        goalDuration: Double,
        currentAbsHour: Double,
        period: Double = 24
    ) -> PredictionInput? {
        guard !records.isEmpty else { return nil }

        let sorted = records.sorted { $0.day < $1.day }
        let recent = Array(sorted.suffix(7))
        guard let latest = recent.last else { return nil }

        // -- Temporal encoding --
        let clockHour = currentAbsHour.truncatingRemainder(dividingBy: 24)
        let angle = (2 * Double.pi * clockHour) / 24
        let sinH = sin(angle)
        let cosH = cos(angle)

        // -- Calendar --
        let todayWeekend: Double = latest.isWeekend ? 1.0 : 0.0
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: latest.date) ?? latest.date
        let weekday = cal.component(.weekday, from: tomorrow)
        let tomorrowWeekend: Double = (weekday == 1 || weekday == 7) ? 1.0 : 0.0

        // -- Rolling 7d stats --
        let bedtimes = recent.map(\.bedtimeHour)
        let wakes = recent.map(\.wakeupHour)
        let meanBed = circularMeanHour(bedtimes)
        let meanWake = wakes.reduce(0, +) / Double(wakes.count)
        let stdBed = circularStdHour(bedtimes)

        // -- Sleep pressure --
        let meanDuration = recent.map(\.sleepDuration).reduce(0, +) / Double(recent.count)
        let debt = meanDuration - goalDuration

        // Estimate current Process S using continuous cross-day propagation
        let clockHourInt = Int(clockHour)
        let currentS = continuousProcessS(from: recent, currentHour: clockHourInt)

        // -- Circadian --
        let acro = latest.cosinor.acrophase
        let r2 = latest.cosinor.r2

        // -- Events today --
        // Today = events whose absoluteHour falls within the current day
        let todayStart = Double(latest.day) * period
        let todayEnd = todayStart + period
        let todayEvents = events.filter { $0.absoluteHour >= todayStart && $0.absoluteHour < todayEnd }

        let exerciseCount = Double(todayEvents.filter { $0.type == .exercise }.count)
        let caffeineCount = Double(todayEvents.filter { $0.type == .caffeine }.count)
        let melatoninCount = Double(todayEvents.filter { $0.type == .melatonin }.count)
        let stressCount = Double(todayEvents.filter { $0.type == .stress }.count)
        let alcoholCount = Double(todayEvents.filter { $0.type == .alcohol }.count)

        // -- Drift --
        let drift: Double
        if recent.count >= 2 {
            let drifts = recent.map(\.driftMinutes)
            let firstHalf = drifts.prefix(drifts.count / 2)
            let secondHalf = drifts.suffix(drifts.count / 2)
            let avgFirst = firstHalf.isEmpty ? 0 : firstHalf.reduce(0, +) / Double(firstHalf.count)
            let avgSecond = secondHalf.isEmpty ? 0 : secondHalf.reduce(0, +) / Double(secondHalf.count)
            drift = (avgSecond - avgFirst) / Double(max(1, recent.count - 1))
        } else {
            drift = 0
        }

        // -- Consistency --
        let conScore = Double(consistency?.score ?? 50)

        // -- Chronotype shift --
        // Offset from intermediate (23.5 midpoint of 23-24 bed range) in hours
        let chronoShift: Double
        if let ct = chronotypeResult {
            let idealMid = (ct.chronotype.idealBedRange.0 + ct.chronotype.idealBedRange.1) / 2
            chronoShift = circularDiff(idealMid, 23.5)
        } else {
            chronoShift = 0
        }

        return PredictionInput(
            sinHour: sinH, cosHour: cosH,
            isWeekend: todayWeekend, isTomorrowWeekend: tomorrowWeekend,
            meanBedtime7d: meanBed, meanWake7d: meanWake, stdBedtime7d: stdBed,
            sleepDebt: debt, lastSleepDuration: latest.sleepDuration, processS: currentS,
            acrophase: acro, cosinorR2: r2,
            exerciseToday: exerciseCount, caffeineToday: caffeineCount,
            melatoninToday: melatoninCount, stressToday: stressCount, alcoholToday: alcoholCount,
            driftRate: drift, consistencyScore: conScore, chronotypeShift: chronoShift,
            dataCount: recent.count
        )
    }

    // MARK: - Continuous Process S

    /// Compute Process S using cross-day debt propagation from the last 7 days.
    ///
    /// Calls `TwoProcessModel.computeContinuous` to propagate sleep debt across
    /// multiple days, then extracts the S value for the current hour on the last day.
    /// Falls back to the stateless `processS()` if fewer than 2 records are available.
    ///
    /// - Parameters:
    ///   - records: Recent sleep records (sorted ascending by day).
    ///   - currentHour: Current clock hour (0-23).
    /// - Returns: Process S value in the range [0, 1].
    public static func continuousProcessS(from records: [SleepRecord], currentHour: Int) -> Double {
        let sorted = records.sorted { $0.day < $1.day }
        let recent = Array(sorted.suffix(7))

        guard recent.count >= 2 else {
            // Fall back to stateless processS
            guard let latest = recent.last else {
                return TwoProcessModel.processS(hoursSinceTransition: 0, isAwake: true, s0: 0.2)
            }
            let hoursSinceWake = max(0, Double(currentHour) - latest.wakeupHour)
            return TwoProcessModel.processS(hoursSinceTransition: hoursSinceWake, isAwake: true, s0: 0.2)
        }

        let points = TwoProcessModel.computeContinuous(recent)

        // computeContinuous uses 0-based day indices matching array position
        let lastDayIndex = recent.count - 1

        // Find the point matching currentHour on the last day
        let clampedHour = max(0, min(23, currentHour))
        if let match = points.last(where: { $0.day == lastDayIndex && $0.hour == clampedHour }) {
            return match.s
        }

        // If no exact hour match, use the last point from the last day
        if let lastPoint = points.last(where: { $0.day == lastDayIndex }) {
            return lastPoint.s
        }

        // Ultimate fallback: stateless
        guard let latest = recent.last else { return 0.5 }
        let hoursSinceWake = max(0, Double(currentHour) - latest.wakeupHour)
        return TwoProcessModel.processS(hoursSinceTransition: hoursSinceWake, isAwake: true, s0: 0.2)
    }

    // MARK: - Circular helpers (duplicated from SpiralConsistencyCalculator pattern)

    /// Map late-night bedtime hours (0-6) to 24-30 for correct circular math.
    private static func normalizeHour(_ h: Double) -> Double {
        h < 12 ? h + 24 : h
    }

    /// Circular mean of clock hours (handles midnight wrap).
    static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 23 }
        let normalized = hours.map(normalizeHour)
        let mean = normalized.reduce(0, +) / Double(normalized.count)
        return mean.truncatingRemainder(dividingBy: 24)
    }

    /// Circular standard deviation of clock hours.
    static func circularStdHour(_ hours: [Double]) -> Double {
        guard hours.count > 1 else { return 0 }
        let mu = circularMeanHour(hours)
        let diffs = hours.map { abs(circularDiff($0, mu)) }
        let variance = diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)
        return sqrt(variance)
    }

    /// Signed circular difference on a 24h clock (hours).
    static func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = normalizeHour(a) - normalizeHour(b)
        if d > 12 { d -= 24 }
        if d < -12 { d += 24 }
        return d
    }
}
