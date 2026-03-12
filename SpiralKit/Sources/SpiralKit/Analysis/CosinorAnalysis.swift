import Foundation

/// Cosinor Analysis Engine
///
/// Fits a cosine curve Y(t) = MESOR + Amplitude × cos(ω×t + φ) to time-series activity data.
/// Port of src/utils/cosinor.js from the Spiral Journey web project.
///
/// References:
///   - Cornelissen, G. (2014). Cosinor-based rhythmometry.
///   - Refinetti et al. (2007). Procedures for numerical analysis of circadian rhythms.
public enum CosinorAnalysis {

    /// Single cosinor fit to hourly activity data.
    /// - Parameters:
    ///   - data: Array of (hour, activity) pairs. activity is 0-1.
    ///   - periodHours: Expected period (default 24h)
    /// - Returns: CosinorResult with mesor, amplitude, acrophase, period, r2
    public static func fit(_ data: [HourlyActivity], periodHours: Double = 24) -> CosinorResult {
        guard data.count >= 3 else {
            return CosinorResult.empty
        }

        let n = Double(data.count)
        let omega = (2 * Double.pi) / periodHours

        var sumY = 0.0, sumCos = 0.0, sumSin = 0.0
        var sumCos2 = 0.0, sumSin2 = 0.0, sumCosSin = 0.0
        var sumYCos = 0.0, sumYSin = 0.0, sumY2 = 0.0

        for d in data {
            let t = Double(d.hour)
            let y = d.activity
            let c = cos(omega * t)
            let s = sin(omega * t)

            sumY += y
            sumCos += c
            sumSin += s
            sumCos2 += c * c
            sumSin2 += s * s
            sumCosSin += c * s
            sumYCos += y * c
            sumYSin += y * s
            sumY2 += y * y
        }

        let mesor = sumY / n
        let cMean = sumCos / n
        let sMean = sumSin / n

        let ccVar = sumCos2 / n - cMean * cMean
        let ssVar = sumSin2 / n - sMean * sMean
        let csVar = sumCosSin / n - cMean * sMean
        let ycVar = sumYCos / n - mesor * cMean
        let ysVar = sumYSin / n - mesor * sMean

        let det = ccVar * ssVar - csVar * csVar
        guard abs(det) > 1e-10 else {
            return CosinorResult(mesor: mesor, amplitude: 0, acrophase: 0, period: periodHours, r2: 0)
        }

        let beta  = (ycVar * ssVar - ysVar * csVar) / det
        let gamma = (ysVar * ccVar - ycVar * csVar) / det

        let amplitude = sqrt(beta * beta + gamma * gamma)
        let acrophaseRad = atan2(-gamma, beta)
        // Convert radians back to hours, keeping in [0, period)
        let raw = (-acrophaseRad / omega).truncatingRemainder(dividingBy: periodHours)
        let acrophaseHours = (raw + periodHours).truncatingRemainder(dividingBy: periodHours)

        let ssTotal = sumY2 / n - mesor * mesor
        let ssResid = ssTotal - (beta * ycVar + gamma * ysVar)
        let r2 = ssTotal > 0 ? 1 - ssResid / ssTotal : 0.0

        return CosinorResult(
            mesor: max(0, mesor),
            amplitude: max(0, amplitude),
            acrophase: acrophaseHours,
            period: periodHours,
            r2: max(0, min(1, r2))
        )
    }

    /// Sliding window cosinor analysis.
    /// - Parameters:
    ///   - records: Array of SleepRecord objects with hourlyActivity
    ///   - windowDays: Window size in days (default 7)
    /// - Returns: Array of CosinorResult indexed by center day
    public static func slidingFit(_ records: [SleepRecord], windowDays: Int = 7) -> [(dayIndex: Int, result: CosinorResult)] {
        var results: [(dayIndex: Int, result: CosinorResult)] = []
        guard records.count >= windowDays else { return results }

        for i in 0...(records.count - windowDays) {
            let windowData = records[i..<(i + windowDays)].flatMap { $0.hourlyActivity }
            let fitResult = fit(windowData)
            results.append((dayIndex: i + windowDays / 2, result: fitResult))
        }
        return results
    }

    /// Calculate acrophase drift between consecutive days.
    /// Handles wrap-around at 24h.
    public static func acrophaseDrift(_ results: [CosinorResult]) -> [(day: Int, drift: Double, cumulativeDrift: Double)] {
        var cumulative = 0.0
        return results.enumerated().map { (i, result) in
            guard i > 0 else { return (day: 0, drift: 0, cumulativeDrift: 0) }
            var drift = result.acrophase - results[i - 1].acrophase
            if drift > 12  { drift -= 24 }
            if drift < -12 { drift += 24 }
            cumulative += drift
            return (day: i, drift: drift, cumulativeDrift: cumulative)
        }
    }

    /// Rhythm stability score (0-1) based on circular standard deviation of acrophase across days.
    /// Uses circular statistics to correctly handle wrap-around at midnight (e.g. 23:00 vs 01:00).
    public static func rhythmStability(_ results: [CosinorResult]) -> Double {
        guard !results.isEmpty else { return 0 }
        let acrophases = results.map(\.acrophase)
        // Circular std: convert hours to radians on a 24h circle
        let toRad = Double.pi / 12.0
        let sinMean = acrophases.map { sin($0 * toRad) }.reduce(0, +) / Double(acrophases.count)
        let cosMean = acrophases.map { cos($0 * toRad) }.reduce(0, +) / Double(acrophases.count)
        let R = min(max(sqrt(sinMean * sinMean + cosMean * cosMean), 0), 1)
        // Circular std in hours; R=1 → std=0 (perfect), R~0 → std large
        let stdHours = R > 1e-9 ? sqrt(max(-2.0 * log(R), 0)) / toRad : 12.0
        // Map: std=0 → 1.0 (100%), std=6h → 0 (complete disorder)
        return max(0, min(1, 1 - stdHours / 6.0))
    }
}
