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
}
