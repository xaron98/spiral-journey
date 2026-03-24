import Foundation

/// A 16-feature normalized vector encoding a single day's sleep and context data.
///
/// The nucleotide is split into two "strands":
/// - **Strand 1 (features 0-7):** Sleep timing and physiology
/// - **Strand 2 (features 8-15):** Behavioral context and quality
///
/// All features are normalized to [0, 1] (or [-1, 1] for drift).
public struct DayNucleotide: Codable, Sendable {
    /// The day index this nucleotide represents.
    public let day: Int

    /// 16-element feature vector.
    public let features: [Double]

    /// Total number of features per nucleotide.
    public static let featureCount = 16

    // MARK: - Feature indices

    public enum Feature: Int, CaseIterable, Sendable {
        case bedtimeSin = 0
        case bedtimeCos = 1
        case wakeupSin = 2
        case wakeupCos = 3
        case sleepDuration = 4
        case processS = 5
        case cosinorAcrophase = 6
        case cosinorR2 = 7
        case caffeine = 8
        case exercise = 9
        case alcohol = 10
        case melatonin = 11
        case stress = 12
        case isWeekend = 13
        case driftMinutes = 14
        case sleepQuality = 15
    }

    /// Subscript by feature enum for convenient access.
    public subscript(feature: Feature) -> Double {
        features[feature.rawValue]
    }

    // MARK: - Encoding

    /// Encode a sleep record and its associated circadian events into a nucleotide.
    ///
    /// - Parameters:
    ///   - record: The day's sleep record.
    ///   - events: All circadian events; only those within this day's time window are used.
    ///   - processS: Two-process model sleep pressure value, already in [0, 1].
    ///   - period: Hours per day (default 24).
    ///   - goalDuration: Target sleep duration in hours for quality calculation (default 8).
    public static func encode(
        record: SleepRecord,
        events: [CircadianEvent],
        processS: Double = 0.5,
        period: Double = 24,
        goalDuration: Double = 8
    ) -> DayNucleotide {
        var f = [Double](repeating: 0, count: featureCount)

        // --- Strand 1: Sleep ---

        // Features 0-1: bedtimeHour (circular encoding)
        let bedRad = 2 * Double.pi * record.bedtimeHour / 24
        f[Feature.bedtimeSin.rawValue] = sin(bedRad)
        f[Feature.bedtimeCos.rawValue] = cos(bedRad)

        // Features 2-3: wakeupHour (circular encoding)
        let wakeRad = 2 * Double.pi * record.wakeupHour / 24
        f[Feature.wakeupSin.rawValue] = sin(wakeRad)
        f[Feature.wakeupCos.rawValue] = cos(wakeRad)

        // Feature 4: sleepDuration normalized to [0, 1] via /12
        f[Feature.sleepDuration.rawValue] = min(record.sleepDuration / 12.0, 1.0)

        // Feature 5: process S (already [0, 1])
        f[Feature.processS.rawValue] = clamp01(processS)

        // Feature 6: cosinor acrophase normalized to [0, 1] via /24
        f[Feature.cosinorAcrophase.rawValue] = record.cosinor.acrophase / 24.0

        // Feature 7: cosinor R-squared (already [0, 1])
        f[Feature.cosinorR2.rawValue] = clamp01(record.cosinor.r2)

        // --- Strand 2: Context ---

        // Filter events to this day's time window: [day * period, (day+1) * period)
        let dayStart = Double(record.day) * period
        let dayEnd = dayStart + period
        let dayEvents = events.filter { $0.absoluteHour >= dayStart && $0.absoluteHour < dayEnd }

        // Single-pass event counting (avoids 5 separate filter passes)
        var eventCounts: [EventType: Int] = [:]
        for event in dayEvents { eventCounts[event.type, default: 0] += 1 }

        // Feature 8: caffeine count / 5
        f[Feature.caffeine.rawValue] = min(Double(eventCounts[.caffeine] ?? 0) / 5.0, 1.0)

        // Feature 9: exercise — binary (any exercise event)
        f[Feature.exercise.rawValue] = min(Double(eventCounts[.exercise] ?? 0), 1.0)

        // Feature 10: alcohol count / 3
        f[Feature.alcohol.rawValue] = min(Double(eventCounts[.alcohol] ?? 0) / 3.0, 1.0)

        // Feature 11: melatonin — binary
        f[Feature.melatonin.rawValue] = min(Double(eventCounts[.melatonin] ?? 0), 1.0)

        // Feature 12: stress count / 3
        f[Feature.stress.rawValue] = min(Double(eventCounts[.stress] ?? 0) / 3.0, 1.0)

        // Feature 13: isWeekend
        f[Feature.isWeekend.rawValue] = record.isWeekend ? 1.0 : 0.0

        // Feature 14: driftMinutes / 120, clamped to [-1, 1]
        f[Feature.driftMinutes.rawValue] = max(-1.0, min(record.driftMinutes / 120.0, 1.0))

        // Feature 15: sleepQuality = min(duration/goalDuration, 1) * cosinorR2
        let durationRatio = min(record.sleepDuration / goalDuration, 1.0)
        f[Feature.sleepQuality.rawValue] = durationRatio * clamp01(record.cosinor.r2)

        return DayNucleotide(day: record.day, features: f)
    }

    // MARK: - Private helpers

    private static func clamp01(_ v: Double) -> Double {
        max(0, min(v, 1))
    }
}
