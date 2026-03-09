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

    public static func detect(from records: [SleepRecord]) -> [DisorderSignature] {
        guard records.count >= 7 else { return [] }

        var signatures: [DisorderSignature] = []

        let acrophases = records.map(\.cosinor.acrophase)
        let amplitudes = records.map(\.cosinor.amplitude)
        let r2values   = records.map(\.cosinor.r2)

        let n = Double(acrophases.count)
        let meanAcrophase = acrophases.reduce(0, +) / n
        let meanAmplitude = amplitudes.reduce(0, +) / n
        let meanR2        = r2values.reduce(0, +) / n

        let acroVariance  = acrophases.reduce(0) { $0 + ($1 - meanAcrophase) * ($1 - meanAcrophase) } / n
        let acroStd       = sqrt(acroVariance)

        // Linear trend of acrophase (least squares slope)
        var sumXY = 0.0, sumX = 0.0, sumY = 0.0, sumX2 = 0.0
        for (i, a) in acrophases.enumerated() {
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
