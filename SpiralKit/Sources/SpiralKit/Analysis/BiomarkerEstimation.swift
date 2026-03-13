import Foundation

/// Circadian biomarker position estimation.
/// Port of src/utils/biomarkers.js from the Spiral Journey web project.
public enum BiomarkerEstimation {

    /// Estimate all circadian biomarkers for a given sleep record.
    public static func estimate(from record: SleepRecord) -> [BiomarkerEstimate] {
        [
            BiomarkerEstimate(
                id: "dlmo",
                label: "DLMO",
                hour: ((record.bedtimeHour - 2) + 24).truncatingRemainder(dividingBy: 24),
                description: "Dim Light Melatonin Onset",
                hexColor: "#6e3fa0",
                symbol: "triangle"
            ),
            BiomarkerEstimate(
                id: "car",
                label: "CAR",
                hour: (record.wakeupHour + 0.625).truncatingRemainder(dividingBy: 24), // ~37.5 min post-wake
                description: "Cortisol Awakening Response",
                hexColor: "#f5c842",
                symbol: "diamond"
            ),
            BiomarkerEstimate(
                id: "tempNadir",
                label: "Tmin",
                hour: 4.0,
                description: "Core Temperature Nadir",
                hexColor: "#5b8bd4",
                symbol: "square"
            ),
            BiomarkerEstimate(
                id: "postLunchDip",
                label: "PLD",
                hour: 14.5,
                description: "Post-Lunch Dip",
                hexColor: "#ff8c42",
                symbol: "circle"
            ),
        ]
    }

    // MARK: - Personalized Estimation

    private static func mod24(_ h: Double) -> Double {
        ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
    }

    /// Personalized biomarker estimation anchored to the individual's sleep midpoint.
    ///
    /// Unlike `estimate(from:)` which uses a fixed Tmin of 04:00,
    /// this method derives Tmin from the midpoint of sleep (± 1h),
    /// consistent with Czeisler et al. (1999) and Duffy & Dijk (2002).
    /// All biomarkers include confidence ranges reflecting measurement uncertainty.
    ///
    /// - Parameter record: A single night's sleep data
    /// - Returns: Array of personalized BiomarkerEstimate with confidence intervals
    public static func estimatePersonalized(from record: SleepRecord) -> [BiomarkerEstimate] {
        // Sleep midpoint — the best proxy for circadian phase from sleep timing alone.
        // On free days it approximates DLMO + ~7h (Roenneberg et al., 2004).
        let midpoint = mod24(record.bedtimeHour + record.sleepDuration / 2.0)

        // Tmin ≈ midpoint + 1h — core temperature reaches its minimum
        // roughly 1h after the midpoint of sleep (Czeisler et al., 1999).
        let tmin = mod24(midpoint + 1.0)

        // DLMO ≈ Tmin − 7h — melatonin onset occurs ~7h before the temperature nadir
        // (Pandi-Perumal et al., 2007; Brown et al., 2021).
        let dlmo = mod24(tmin - 7.0)

        // CAR — cortisol peaks 30-45 min after waking (Clow et al., 2010).
        // We use 37.5 min (midpoint of the evidence range).
        let car = mod24(record.wakeupHour + 0.625)

        // PLD — the post-lunch dip is tied to the ~12h circasemidian harmonic
        // of temperature. PLD ≈ Tmin + 10.5h (Monk, 2005).
        let pld = mod24(tmin + 10.5)

        return [
            BiomarkerEstimate(
                id: "dlmo",
                label: "DLMO",
                hour: dlmo,
                description: "Dim Light Melatonin Onset",
                hexColor: "#6e3fa0",
                symbol: "triangle",
                confidenceLow: mod24(dlmo - 1.5),
                confidenceHigh: mod24(dlmo + 1.5)
            ),
            BiomarkerEstimate(
                id: "car",
                label: "CAR",
                hour: car,
                description: "Cortisol Awakening Response",
                hexColor: "#f5c842",
                symbol: "diamond",
                confidenceLow: mod24(car - 0.25),
                confidenceHigh: mod24(car + 0.25)
            ),
            BiomarkerEstimate(
                id: "tempNadir",
                label: "Tmin",
                hour: tmin,
                description: "Core Temperature Nadir",
                hexColor: "#5b8bd4",
                symbol: "square",
                confidenceLow: mod24(tmin - 1.0),
                confidenceHigh: mod24(tmin + 1.0)
            ),
            BiomarkerEstimate(
                id: "postLunchDip",
                label: "PLD",
                hour: pld,
                description: "Post-Lunch Dip",
                hexColor: "#ff8c42",
                symbol: "circle",
                confidenceLow: mod24(pld - 1.5),
                confidenceHigh: mod24(pld + 1.5)
            ),
        ]
    }
}
