import Foundation

/// Change-point detection for circadian rhythm disruptions.
///
/// Detects abrupt transitions in sleep timing (jet lag, shift changes,
/// schedule disruptions) using a simplified PELT algorithm with BIC penalty.
///
/// Reference: Killick, Fearnhead & Eckley (2012). Optimal detection of
/// changepoints with a linear computational cost. JASA.
public enum ChangePointDetection {

    public struct ChangePoint: Sendable {
        public let index: Int       // Day index where change occurs
        public let metric: String   // Which metric changed (e.g. "acrophase", "bedtime", "sri")
        public let magnitude: Double // Size of the shift
    }

    // MARK: - Circular Helpers

    /// Circular mean for clock-hour data (0-24h).
    private static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let toRad = Double.pi / 12.0
        let n = Double(hours.count)
        let sinMean = hours.map { sin($0 * toRad) }.reduce(0, +) / n
        let cosMean = hours.map { cos($0 * toRad) }.reduce(0, +) / n
        guard abs(sinMean) > 1e-9 || abs(cosMean) > 1e-9 else { return 0 }
        var angle = atan2(sinMean, cosMean) / toRad
        if angle < 0 { angle += 24 }
        return angle
    }

    /// Signed circular difference in hours (result in -12...12).
    private static func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d >  12 { d -= 24 }
        while d < -12 { d += 24 }
        return d
    }

    /// Sum of squared circular deviations from the circular mean.
    /// Used as cost function for change-point detection on clock-hour metrics.
    private static func circularSegmentCost(_ segment: [Double]) -> Double {
        guard segment.count > 0 else { return 0 }
        let mu = circularMeanHour(segment)
        return segment.reduce(0) { sum, val in
            let diff = circularDiff(val, mu)
            return sum + diff * diff
        }
    }

    // MARK: - Detection

    /// Detect change points in a univariate time series.
    ///
    /// Uses a simplified PELT approach: tests every possible split point
    /// and accepts it if the two-segment model reduces cost by more than
    /// the BIC penalty term.
    ///
    /// - Parameters:
    ///   - values: Time series values (one per day)
    ///   - minSegment: Minimum segment length (default 3)
    ///   - circular: If true, uses circular cost function (for clock-hour data like acrophase/bedtime)
    /// - Returns: Array of indices where changes are detected
    public static func detect(values: [Double], minSegment: Int = 3, circular: Bool = false) -> [Int] {
        let n = values.count
        guard n >= minSegment * 2 else { return [] }

        let penalty = 2.0 * log(Double(n))  // BIC-style penalty

        func linearSegmentCost(_ start: Int, _ end: Int) -> Double {
            guard end > start else { return 0 }
            let segment = Array(values[start..<end])
            let mean = segment.reduce(0, +) / Double(segment.count)
            return segment.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        }

        func segmentCost(_ start: Int, _ end: Int) -> Double {
            guard end > start else { return 0 }
            if circular {
                return circularSegmentCost(Array(values[start..<end]))
            } else {
                return linearSegmentCost(start, end)
            }
        }

        let totalCost = segmentCost(0, n)
        var changePoints: [Int] = []

        // Greedy single-pass: find the split that maximally reduces cost
        var bestSplit = -1
        var bestReduction = 0.0

        for k in minSegment..<(n - minSegment + 1) {
            let leftCost = segmentCost(0, k)
            let rightCost = segmentCost(k, n)
            let reduction = totalCost - (leftCost + rightCost)
            if reduction > penalty && reduction > bestReduction {
                bestReduction = reduction
                bestSplit = k
            }
        }

        if bestSplit >= 0 {
            changePoints.append(bestSplit)
        }

        return changePoints.sorted()
    }

    /// Detect change points across multiple circadian metrics.
    ///
    /// Analyzes acrophase, bedtime, and sleep duration series for abrupt shifts.
    /// Each detected point includes which metric triggered it and the shift magnitude.
    /// Uses circular arithmetic for acrophase and bedtime (clock-hour data).
    public static func detectInRecords(_ records: [SleepRecord]) -> [ChangePoint] {
        guard records.count >= 6 else { return [] }

        var results: [ChangePoint] = []

        let acrophases = records.map(\.cosinor.acrophase)
        let bedtimes = records.map(\.bedtimeHour)
        let durations = records.map(\.sleepDuration)

        // (name, values, isCircular)
        let metrics: [(String, [Double], Bool)] = [
            ("acrophase", acrophases, true),
            ("bedtime", bedtimes, true),
            ("duration", durations, false),
        ]

        for (name, values, isCircular) in metrics {
            let points = detect(values: values, circular: isCircular)
            for idx in points {
                let before = Array(values[0..<idx])
                let after = Array(values[idx..<values.count])

                let magnitude: Double
                if isCircular {
                    let meanBefore = circularMeanHour(before)
                    let meanAfter = circularMeanHour(after)
                    magnitude = abs(circularDiff(meanAfter, meanBefore))
                } else {
                    let meanBefore = before.reduce(0, +) / Double(before.count)
                    let meanAfter = after.reduce(0, +) / Double(after.count)
                    magnitude = abs(meanAfter - meanBefore)
                }

                results.append(ChangePoint(
                    index: idx,
                    metric: name,
                    magnitude: magnitude
                ))
            }
        }

        return results.sorted { $0.index < $1.index }
    }
}
