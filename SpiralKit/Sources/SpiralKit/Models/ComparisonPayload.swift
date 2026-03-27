import Foundation

/// Summary of a peer's sleep profile for comparison.
/// Contains only aggregated metrics — no raw records, phases, or events.
public struct ComparisonPayload: Codable, Sendable {
    public let alias: String
    public let consistencyScore: Int           // 0-100
    public let meanDuration: Double            // hours
    public let sleepRegularityIndex: Double    // 0-100
    public let socialJetlag: Double            // hours
    public let chronotype: String              // "morning" / "intermediate" / "evening"
    public let meanAcrophase: Double           // hour of day (0-24)
    public let meanBedtime: Double             // hour of day
    public let meanWake: Double                // hour of day
    public let periodogramPeaks: [PeakSummary]
    public let circadianCoherence: Double      // 0-1
    public let fragmentationScore: Double      // 0-1
    public let recordCount: Int

    // MARK: - NeuroSpiral torus metrics (nil if unavailable)

    /// Distribution of dominant tesseract vertices across nights (16 elements, sums to 1.0)
    public let vertexDistribution: [Double]?
    /// Mean winding ratio ω₁/ω₂ across analyzed nights
    public let meanWindingRatio: Double?
    /// Torus stability: fraction of time in dominant vertex (0-1)
    public let torusStability: Double?
    /// Dominant tesseract vertex (0-15)
    public let dominantVertex: Int?

    public init(
        alias: String, consistencyScore: Int, meanDuration: Double,
        sleepRegularityIndex: Double, socialJetlag: Double, chronotype: String,
        meanAcrophase: Double, meanBedtime: Double, meanWake: Double,
        periodogramPeaks: [PeakSummary], circadianCoherence: Double,
        fragmentationScore: Double, recordCount: Int,
        vertexDistribution: [Double]? = nil, meanWindingRatio: Double? = nil,
        torusStability: Double? = nil, dominantVertex: Int? = nil
    ) {
        self.alias = alias
        self.consistencyScore = consistencyScore
        self.meanDuration = meanDuration
        self.sleepRegularityIndex = sleepRegularityIndex
        self.socialJetlag = socialJetlag
        self.chronotype = chronotype
        self.meanAcrophase = meanAcrophase
        self.meanBedtime = meanBedtime
        self.meanWake = meanWake
        self.periodogramPeaks = periodogramPeaks
        self.circadianCoherence = circadianCoherence
        self.fragmentationScore = fragmentationScore
        self.recordCount = recordCount
        self.vertexDistribution = vertexDistribution
        self.meanWindingRatio = meanWindingRatio
        self.torusStability = torusStability
        self.dominantVertex = dominantVertex
    }
}

/// Lightweight periodogram peak for sharing.
public struct PeakSummary: Codable, Sendable {
    public let period: Double
    public let power: Double
    public let label: String?

    public init(period: Double, power: Double, label: String?) {
        self.period = period
        self.power = power
        self.label = label
    }
}

// MARK: - Builder

extension ComparisonPayload {

    /// Build from existing store data. No new computation needed.
    public static func build(
        alias: String,
        analysis: AnalysisResult,
        dnaProfile: SleepDNAProfile?,
        records: [SleepRecord]
    ) -> ComparisonPayload {
        let stats = analysis.stats

        // Periodogram peaks
        let peaks: [PeakSummary] = (analysis.periodogramResults ?? []).flatMap { result in
            result.peaks.map { PeakSummary(period: $0.period, power: $0.power, label: $0.label?.rawValue) }
        }

        // Chronotype label
        let acro = stats.meanAcrophase
        let chronoLabel: String
        if acro < 13 { chronoLabel = "morning" }
        else if acro > 16 { chronoLabel = "evening" }
        else { chronoLabel = "intermediate" }

        // Mean bedtime/wake from last 14 records
        let recent = records.suffix(14)
        let meanBed = recent.isEmpty ? 23.0 : recent.map(\.bedtimeHour).reduce(0, +) / Double(recent.count)
        let meanWake = recent.isEmpty ? 7.0 : recent.map(\.wakeupHour).reduce(0, +) / Double(recent.count)

        return ComparisonPayload(
            alias: alias,
            consistencyScore: analysis.consistency?.score ?? 0,
            meanDuration: stats.meanSleepDuration,
            sleepRegularityIndex: stats.sri,
            socialJetlag: stats.socialJetlag,
            chronotype: chronoLabel,
            meanAcrophase: acro,
            meanBedtime: meanBed,
            meanWake: meanWake,
            periodogramPeaks: peaks,
            circadianCoherence: dnaProfile?.healthMarkers.circadianCoherence ?? 0,
            fragmentationScore: dnaProfile?.healthMarkers.fragmentationScore ?? 0,
            recordCount: records.count,
            vertexDistribution: analysis.neuroSpiralVertexDistribution,
            meanWindingRatio: analysis.neuroSpiralWindingRatio,
            torusStability: analysis.neuroSpiralStability,
            dominantVertex: analysis.neuroSpiralDominantVertex
        )
    }

    // MARK: - Torus Similarity

    /// Compare two users' vertex distributions via Jensen-Shannon divergence.
    /// Returns similarity in [0, 1] where 1 = identical distributions.
    public static func torusSimilarity(
        _ distA: [Double]?,
        _ distB: [Double]?
    ) -> Double? {
        guard let a = distA, let b = distB,
              a.count == 16, b.count == 16 else { return nil }

        let m = zip(a, b).map { ($0 + $1) / 2.0 }
        let jsd = (kl(a, m) + kl(b, m)) / 2.0
        return max(0, 1.0 - jsd / log(2.0))
    }

    private static func kl(_ p: [Double], _ q: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<p.count {
            if p[i] > 1e-10 && q[i] > 1e-10 {
                sum += p[i] * log(p[i] / q[i])
            }
        }
        return sum
    }
}
