import Foundation

/// Baseline heuristic prediction engine for sleep timing.
///
/// Uses weighted averages of recent sleep data + event-based adjustments.
/// No ML dependency — works from day 1 with minimal data.
///
/// Follows the `public enum` + static methods convention of SpiralKit engines.
public enum HeuristicPredictionEngine {

    /// Predict tonight's sleep from the feature vector.
    ///
    /// Algorithm:
    /// 1. Exponentially-weighted mean of recent bedtimes (α=0.7, recent → heavy)
    /// 2. Weekend shift (+socialJetlag proxy)
    /// 3. Event adjustments (caffeine, exercise, melatonin, stress, alcohol)
    /// 4. Sleep pressure correction (Process S > threshold → earlier bed)
    /// 5. Drift correction (damped trend continuation)
    /// 6. Wake = bed + typical duration (clamped 5-11h)
    ///
    /// - Returns: A `PredictionOutput` with predicted bed/wake times and confidence.
    public static func predict(from input: PredictionInput, targetDate: Date = Date()) -> PredictionOutput {

        // ── 1. Base bedtime: exponentially-weighted mean ──
        // meanBedtime7d already captures the central tendency.
        // We use it as the anchor and apply adjustments on top.
        var bed = input.meanBedtime7d

        // ── 2. Weekend adjustment ──
        // On weekend nights people tend to go to bed later.
        // stdBedtime7d serves as a proxy for how variable the user is.
        if input.isTomorrowWeekend > 0.5 {
            let shift = min(input.stdBedtime7d * 0.8, 1.5) // cap at 1.5h
            bed += shift
        }

        // ── 3. Event adjustments ──
        if input.exerciseToday > 0  { bed -= 0.25 }                              // 15 min earlier
        if input.caffeineToday > 0  { bed += 0.50 + (input.caffeineToday - 1) * 0.25 } // 30+ min later
        if input.melatoninToday > 0 { bed -= 0.33 }                              // 20 min earlier
        if input.stressToday > 0    { bed += 0.25 }                              // 15 min later
        if input.alcoholToday > 0   { bed -= 0.17 }                              // 10 min earlier onset

        // ── 4. Sleep pressure correction ──
        // High Process S (>0.65) indicates accumulated fatigue → earlier bed.
        if input.processS > 0.65 {
            let excess = input.processS - 0.65
            bed -= excess * 1.5  // up to ~30 min for S=0.85
        }

        // ── 5. Drift correction ──
        // If acrophase is drifting (e.g. delayed), apply a damped correction.
        if abs(input.driftRate) > 5 {
            bed += (input.driftRate / 60) * 0.5 // half of the daily drift, converted to hours
        }

        // ── 6. Chronotype anchor ──
        // Gently pull toward the user's chronotype ideal if data is sparse.
        if input.dataCount < 4 && input.chronotypeShift != 0 {
            bed += input.chronotypeShift * 0.3
        }

        // ── Normalize bedtime to 0-24 range ──
        bed = normalizeTo24(bed)

        // ── 7. Wake prediction ──
        // Use last sleep duration as the best estimate of tonight's length.
        var duration = input.lastSleepDuration
        duration = max(5.0, min(11.0, duration))  // clamp to reasonable range

        var wake = bed + duration
        if wake >= 24 { wake -= 24 }

        // ── 8. Confidence ──
        let confidence = computeConfidence(dataCount: input.dataCount, consistency: input.consistencyScore)

        return PredictionOutput(
            predictedBedtimeHour: bed,
            predictedWakeHour: wake,
            predictedDuration: duration,
            confidence: confidence,
            engine: .heuristic,
            generatedAt: Date(),
            targetDate: targetDate
        )
    }

    // MARK: - Confidence

    private static func computeConfidence(dataCount: Int, consistency: Double) -> PredictionConfidence {
        if dataCount >= 7 && consistency > 60 {
            return .high
        }
        if dataCount >= 4 || consistency > 30 {
            return .medium
        }
        return .low
    }

    // MARK: - Helpers

    private static func normalizeTo24(_ hour: Double) -> Double {
        var h = hour.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        return h
    }
}
