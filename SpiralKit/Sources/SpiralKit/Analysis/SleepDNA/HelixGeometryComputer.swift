import Foundation

// MARK: - Types

/// Per-day geometric parameters for the double-helix Sleep DNA visualization.
public struct DayHelixParams: Codable, Sendable {
    /// Day index matching the source SleepRecord.
    public let day: Int
    /// Twist angle between strands, derived from PLV synchrony.
    public let twistAngle: Double
    /// Helix radius: deviation of midSleep from chronotype ideal.
    public let helixRadius: Double
    /// Strand thickness: proportion of deep (N3) sleep phases [0,1].
    public let strandThickness: Double
    /// Surface roughness: fragmentation measure [0,1].
    public let surfaceRoughness: Double
}

// MARK: - Computer

/// Maps sleep data and synchrony measurements into per-day helix geometry parameters.
public enum HelixGeometryComputer {

    /// Compute helix geometry parameters for each sleep record.
    ///
    /// - Parameters:
    ///   - records: Sleep records to map.
    ///   - basePairs: PLV synchrony measurements from HilbertPhaseAnalyzer.
    ///   - chronotype: Optional chronotype result for ideal midSleep reference.
    ///   - maxTwist: Maximum twist angle in radians (default π/3).
    /// - Returns: One `DayHelixParams` per record.
    public static func compute(
        records: [SleepRecord],
        basePairs: [BasePairSynchrony],
        chronotype: ChronotypeResult?,
        maxTwist: Double = .pi / 3
    ) -> [DayHelixParams] {
        let avgPLV = averagePLV(basePairs)
        let idealMid = idealMidSleep(from: chronotype)

        return records.map { record in
            let twist = avgPLV != nil
                ? avgPLV! * maxTwist
                : 0.5 * maxTwist

            let midSleep = (record.bedtimeHour + record.wakeupHour) / 2.0
            let deviation = abs(circularTimeDiff(midSleep, idealMid))
            let radius = min(deviation / 3.0, 1.0)

            let totalPhases = record.phases.count
            let deepCount = record.phases.filter { $0.phase == .deep }.count
            let thickness = totalPhases > 0 ? Double(deepCount) / Double(totalPhases) : 0

            let awakeCount = record.phases.filter { $0.phase == .awake }.count
            let roughness = min(Double(awakeCount) / 10.0, 1.0)

            return DayHelixParams(
                day: record.day,
                twistAngle: twist,
                helixRadius: radius,
                strandThickness: thickness,
                surfaceRoughness: roughness
            )
        }
    }

    // MARK: - Helpers

    /// Average PLV across all base pairs, or nil if empty.
    private static func averagePLV(_ pairs: [BasePairSynchrony]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        let sum = pairs.reduce(0.0) { $0 + $1.plv }
        return sum / Double(pairs.count)
    }

    /// Ideal mid-sleep hour from chronotype, defaulting to 23.5 (≈ 3:30 AM midpoint for 23:00-8:00).
    private static func idealMidSleep(from chronotype: ChronotypeResult?) -> Double {
        guard let chrono = chronotype else { return 23.5 }
        return chrono.chronotype.idealBedRange.0
    }
}
