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

    public init(
        alias: String, consistencyScore: Int, meanDuration: Double,
        sleepRegularityIndex: Double, socialJetlag: Double, chronotype: String,
        meanAcrophase: Double, meanBedtime: Double, meanWake: Double,
        periodogramPeaks: [PeakSummary], circadianCoherence: Double,
        fragmentationScore: Double, recordCount: Int
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
            recordCount: records.count
        )
    }
}
