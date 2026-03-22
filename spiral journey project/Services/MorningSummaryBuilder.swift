import Foundation
import SpiralKit

/// Generates the morning summary notification text from last night's data.
enum MorningSummaryBuilder {

    struct Summary {
        let title: String
        let body: String
    }

    static func build(
        lastNight: SleepRecord,
        dnaProfile: SleepDNAProfile?,
        consistency: SpiralConsistencyScore?,
        bundle: Bundle
    ) -> Summary {
        let loc = { (key: String) in NSLocalizedString(key, bundle: bundle, comment: "") }

        // Title: based on wake time
        let title = lastNight.wakeupHour >= 12
            ? loc("morning.summary.title.afternoon")
            : loc("morning.summary.title.morning")

        // Body parts
        var parts: [String] = []

        // 1. Duration in Xh Ym format
        let totalMin = Int(lastNight.sleepDuration * 60)
        let hours = totalMin / 60
        let mins = totalMin % 60
        let durationStr = mins == 0
            ? String(format: loc("morning.summary.duration.exact"), hours)
            : String(format: loc("morning.summary.duration"), hours, mins)
        parts.append(durationStr)

        // 2. Rhythm trend
        if let c = consistency, let delta = c.deltaVsPreviousWeek {
            if delta > 2 {
                parts.append(loc("morning.summary.rhythm.improving"))
            } else if delta < -2 {
                parts.append(loc("morning.summary.rhythm.declining"))
            } else {
                parts.append(loc("morning.summary.rhythm.stable"))
            }
        }

        // 3. Actionable tip (first matching rule)
        if let profile = dnaProfile {
            if let tip = caffeineRule(profile, bundle: bundle) {
                parts.append(tip)
            } else if profile.healthMarkers.fragmentationScore > HealthMarkerDetector.fragmentationScoreThreshold * 0.8 {
                parts.append(loc("morning.summary.tip.screens"))
            } else if profile.healthMarkers.driftSeverity > HealthMarkerDetector.driftSeverityThreshold * 0.8 {
                parts.append(loc("morning.summary.tip.schedule"))
            }
        }

        return Summary(title: title, body: parts.joined(separator: ". ") + ".")
    }

    // MARK: - Helpers

    /// Check if caffeine has a strong negative effect on sleep.
    private static func caffeineRule(_ profile: SleepDNAProfile, bundle: Bundle) -> String? {
        // Find caffeine (index 8) in expression rules
        guard let rule = profile.expressionRules.first(where: { $0.regulatorFeatureIndex == 8 }) else {
            return nil
        }
        // Only suggest if caffeine worsens sleep quality
        if rule.qualityWith < rule.qualityWithout && abs(rule.qualityWith - rule.qualityWithout) > 0.05 {
            return NSLocalizedString("morning.summary.tip.caffeine", bundle: bundle, comment: "")
        }
        return nil
    }
}
