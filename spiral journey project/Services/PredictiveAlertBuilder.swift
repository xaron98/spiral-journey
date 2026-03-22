import Foundation
import SpiralKit

/// Evaluates whether a predictive alert should fire based on current week patterns.
enum PredictiveAlertBuilder {

    struct Alert {
        let shouldFire: Bool
        let body: String
    }

    static func evaluate(
        currentWeekRecords: [SleepRecord],
        dnaProfile: SleepDNAProfile?,
        stats: SleepStats,
        bundle: Bundle
    ) -> Alert {
        let loc = { (key: String) in NSLocalizedString(key, bundle: bundle, comment: "") }

        guard let profile = dnaProfile else {
            return Alert(shouldFire: false, body: "")
        }

        // 1. Check if best DTW alignment predicts bad quality tomorrow
        if let bestAlignment = profile.alignments.sorted(by: { $0.similarity > $1.similarity }).first {
            if bestAlignment.similarity > 0.6 {
                // Check the motif quality for that week
                if let motif = profile.motifs.first(where: {
                    $0.instanceWeekIndices.contains(bestAlignment.weekIndex)
                }), motif.avgQuality < 0.4 {
                    return Alert(shouldFire: true, body: loc("predictive.alert.pattern"))
                }
            }
        }

        // 2. Check for nonsense mutation this week
        if let lastMutation = profile.mutations.last,
           lastMutation.classification == .nonsense {
            return Alert(shouldFire: true, body: loc("predictive.alert.mutation"))
        }

        // 3. Check weekly drift
        let drift = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if drift > 1.5 {
            return Alert(shouldFire: true, body: loc("predictive.alert.drift"))
        }

        return Alert(shouldFire: false, body: "")
    }
}
