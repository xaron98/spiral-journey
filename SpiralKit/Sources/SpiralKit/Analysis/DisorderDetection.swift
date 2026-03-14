import Foundation

/// Circadian disorder signature detection.
///
/// Detects patterns associated with:
/// - DSWPD: Delayed Sleep-Wake Phase Disorder
/// - ASWPD: Advanced Sleep-Wake Phase Disorder
/// - N24SWD: Non-24-Hour Sleep-Wake Disorder
/// - ISWRD: Irregular Sleep-Wake Rhythm Disorder
///
/// Port of src/utils/disorderSignatures.js from the Spiral Journey web project.
public enum DisorderDetection {

    // MARK: - Circular Helpers

    /// Circular mean for clock-hour data (0-24h).
    /// Uses sin/cos + atan2 to handle midnight-crossing correctly.
    private static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let toRad = Double.pi / 12.0  // 24h → 2π
        let n = Double(hours.count)
        let sinMean = hours.map { sin($0 * toRad) }.reduce(0, +) / n
        let cosMean = hours.map { cos($0 * toRad) }.reduce(0, +) / n
        guard abs(sinMean) > 1e-9 || abs(cosMean) > 1e-9 else { return 0 }
        var angle = atan2(sinMean, cosMean) / toRad
        // Normalize to [0, 24) — handles floating-point edge cases near 0/24
        if angle < 0 { angle += 24 }
        if angle >= 24 { angle -= 24 }
        return angle
    }

    /// Circular standard deviation for clock-hour data (0-24h).
    /// Returns result in hours.
    private static func circularStdHour(_ hours: [Double]) -> Double {
        guard hours.count > 1 else { return 0 }
        let toRad = Double.pi / 12.0
        let n = Double(hours.count)
        let sinMean = hours.map { sin($0 * toRad) }.reduce(0, +) / n
        let cosMean = hours.map { cos($0 * toRad) }.reduce(0, +) / n
        let R = sqrt(sinMean * sinMean + cosMean * cosMean)
        let R_clamped = min(max(R, 1e-9), 1)
        return sqrt(max(-2.0 * log(R_clamped), 0)) / toRad
    }

    /// Unwrap a series of clock-hour values so that consecutive values
    /// don't jump by more than 12h. This produces a continuous (non-circular)
    /// series suitable for linear regression (drift detection).
    private static func unwrapHours(_ hours: [Double]) -> [Double] {
        guard !hours.isEmpty else { return [] }
        var unwrapped = [hours[0]]
        for i in 1..<hours.count {
            var diff = hours[i] - unwrapped[i - 1]
            if diff > 12 { diff -= 24 }
            if diff < -12 { diff += 24 }
            unwrapped.append(unwrapped[i - 1] + diff)
        }
        return unwrapped
    }

    // MARK: - Detection

    public static func detect(from records: [SleepRecord]) -> [DisorderSignature] {
        guard records.count >= 7 else { return [] }

        var signatures: [DisorderSignature] = []

        let acrophases = records.map(\.cosinor.acrophase)
        let amplitudes = records.map(\.cosinor.amplitude)
        let r2values   = records.map(\.cosinor.r2)

        let n = Double(acrophases.count)
        let meanAcrophase = circularMeanHour(acrophases)
        let meanAmplitude = amplitudes.reduce(0, +) / n
        let meanR2        = r2values.reduce(0, +) / n

        let acroStd       = circularStdHour(acrophases)

        // Linear trend of acrophase using unwrapped values (least squares slope).
        // Unwrapping removes circular discontinuities so linear regression is valid.
        let unwrapped = unwrapHours(acrophases)
        var sumXY = 0.0, sumX = 0.0, sumY = 0.0, sumX2 = 0.0
        for (i, a) in unwrapped.enumerated() {
            let xi = Double(i)
            sumX += xi; sumY += a
            sumXY += xi * a; sumX2 += xi * xi
        }
        let denom = n * sumX2 - sumX * sumX
        let driftSlope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0

        // DSWPD: mean acrophase > 17h, low variance
        if meanAcrophase > 17 && acroStd < 2 {
            let confidence = min(1, (meanAcrophase - 17) / 3 * (2 - acroStd) / 2)
            signatures.append(DisorderSignature(
                id: "dswpd", label: "DSWPD", fullLabel: "Delayed Sleep-Wake Phase",
                confidence: confidence,
                description: String(format: "Late acrophase (%.1fh), stable pattern", meanAcrophase),
                hexColor: "#ff6b6b"
            ))
        }

        // ASWPD: mean acrophase < 12h, low variance
        if meanAcrophase < 12 && acroStd < 2 {
            let confidence = min(1, (12 - meanAcrophase) / 4 * (2 - acroStd) / 2)
            signatures.append(DisorderSignature(
                id: "aswpd", label: "ASWPD", fullLabel: "Advanced Sleep-Wake Phase",
                confidence: confidence,
                description: String(format: "Early acrophase (%.1fh), stable pattern", meanAcrophase),
                hexColor: "#ffd84a"
            ))
        }

        // N24SWD: significant progressive drift (>0.15h/day)
        if abs(driftSlope) > 0.15 && meanR2 > 0.3 {
            let confidence = min(1, (abs(driftSlope) - 0.15) / 0.3)
            let direction = driftSlope > 0 ? "delay" : "advance"
            signatures.append(DisorderSignature(
                id: "n24swd", label: "N24SWD", fullLabel: "Non-24-Hour Rhythm",
                confidence: confidence,
                description: String(format: "Progressive %@ drift (%.1f min/day)", direction, driftSlope * 60),
                hexColor: "#a05ee0"
            ))
        }

        // ISWRD: high acrophase variance + low amplitude + low R-squared
        if acroStd > 3 && meanAmplitude < 0.15 && meanR2 < 0.4 {
            let confidence = min(1, (acroStd - 3) / 3 * (0.4 - meanR2) / 0.4)
            signatures.append(DisorderSignature(
                id: "iswrd", label: "ISWRD", fullLabel: "Irregular Sleep-Wake Rhythm",
                confidence: confidence,
                description: String(format: "High variability (σ=%.1fh), weak rhythm (R²=%.2f)", acroStd, meanR2),
                hexColor: "#70a8f0"
            ))
        }

        // Normal pattern if nothing detected
        if signatures.isEmpty {
            let confidence = min(1, meanR2 * (1 - acroStd / 6))
            signatures.append(DisorderSignature(
                id: "normal", label: "Normal", fullLabel: "Normal Circadian Pattern",
                confidence: confidence,
                description: String(format: "Stable rhythm (acrophase %.1fh ± %.1fh)", meanAcrophase, acroStd),
                hexColor: "#5bffa8"
            ))
        }

        return signatures.sorted { $0.confidence > $1.confidence }
    }
}
