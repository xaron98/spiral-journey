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

    /// Detect change points in a univariate time series.
    ///
    /// Uses a simplified PELT approach: tests every possible split point
    /// and accepts it if the two-segment model reduces cost by more than
    /// the BIC penalty term.
    ///
    /// - Parameters:
    ///   - values: Time series values (one per day)
    ///   - minSegment: Minimum segment length (default 3)
    /// - Returns: Array of indices where changes are detected
    public static func detect(values: [Double], minSegment: Int = 3) -> [Int] {
        let n = values.count
        guard n >= minSegment * 2 else { return [] }

        let penalty = 2.0 * log(Double(n))  // BIC-style penalty

        func segmentCost(_ start: Int, _ end: Int) -> Double {
            guard end > start else { return 0 }
            let segment = Array(values[start..<end])
            let mean = segment.reduce(0, +) / Double(segment.count)
            return segment.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
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
    public static func detectInRecords(_ records: [SleepRecord]) -> [ChangePoint] {
        guard records.count >= 6 else { return [] }

        var results: [ChangePoint] = []

        let acrophases = records.map(\.cosinor.acrophase)
        let bedtimes = records.map(\.bedtimeHour)
        let durations = records.map(\.sleepDuration)

        let metrics: [(String, [Double])] = [
            ("acrophase", acrophases),
            ("bedtime", bedtimes),
            ("duration", durations),
        ]

        for (name, values) in metrics {
            let points = detect(values: values)
            for idx in points {
                let before = Array(values[0..<idx])
                let after = Array(values[idx..<values.count])
                let meanBefore = before.reduce(0, +) / Double(before.count)
                let meanAfter = after.reduce(0, +) / Double(after.count)
                results.append(ChangePoint(
                    index: idx,
                    metric: name,
                    magnitude: abs(meanAfter - meanBefore)
                ))
            }
        }

        return results.sorted { $0.index < $1.index }
    }
}
