import Foundation

/// Intra-night codon analysis: k-mer (k=3) analysis of sleep stage transitions.
///
/// Encodes sleep phases as a 4-letter alphabet (W=Awake, L=Light, D=Deep, R=REM),
/// extracts overlapping triplets, and scores each for architectural integrity.
///
/// References:
///   - k-mer analysis: standard bioinformatics technique for sequence characterization
///   - Sleep architecture: Carskadon & Dement (2011), Principles of Sleep Medicine
public enum SleepCodonAnalyzer {

    // MARK: - Types

    /// A single codon (triplet of sleep phases).
    public struct SleepCodon: Codable, Sendable, Equatable {
        public let phases: [SleepPhase]  // always 3 elements
        public let score: Double          // -1.0 (destructive) to 1.0 (restorative)
        public let label: CodonLabel

        public var code: String {
            phases.map { phaseCode($0) }.joined()
        }
    }

    /// Classification of a codon's function.
    public enum CodonLabel: String, Codable, Sendable {
        case restorative    // good architecture (L→D→R, D→D→R, etc.)
        case neutral        // normal transition
        case fragmented     // disruptive (contains awakenings mid-sleep)
        case destructive    // severely disruptive (REM interruption, repeated awakenings)
    }

    /// Result of analyzing one night's sleep architecture.
    public struct CodonAnalysisResult: Codable, Sendable {
        /// All codons extracted from the night.
        public let codons: [SleepCodon]
        /// Overall architectural integrity score [0, 1].
        public let integrityScore: Double
        /// Count of restorative codons.
        public let restorativeCount: Int
        /// Count of fragmented/destructive codons.
        public let disruptiveCount: Int
        /// Most frequent codon pattern.
        public let dominantCodon: String?
        /// Worst codon (lowest score).
        public let worstCodon: SleepCodon?
        /// True if Watch phase data was available (not just sleep/awake binary).
        public let hasStageData: Bool
    }

    /// Result across multiple nights.
    public struct MultiNightCodonResult: Codable, Sendable {
        /// Per-night analysis.
        public let nightlyResults: [NightCodonSummary]
        /// Mean integrity score across nights.
        public let meanIntegrity: Double
        /// Most common disruptive codon across all nights.
        public let mostCommonDisruption: String?
        /// Trend: positive = improving architecture, negative = worsening.
        public let trend: Double
    }

    public struct NightCodonSummary: Codable, Sendable {
        public let day: Int
        public let integrityScore: Double
        public let totalCodons: Int
        public let disruptiveCount: Int
    }

    // MARK: - Codon Scoring Table

    /// Score table for all 64 possible triplets.
    /// Positive = restorative, negative = disruptive.
    private static let codonScores: [String: (score: Double, label: CodonLabel)] = [
        // Restorative — good sleep architecture
        "LDR": (1.0,  .restorative),   // Classic cycle: light → deep → REM
        "LDD": (0.9,  .restorative),   // Deep consolidation
        "DDR": (0.9,  .restorative),   // Deep to REM transition
        "DRR": (0.8,  .restorative),   // REM continuation after deep
        "RRL": (0.7,  .restorative),   // REM ending naturally into light
        "LDL": (0.6,  .restorative),   // Deep sleep sandwich
        "DRL": (0.6,  .restorative),   // Normal cycle exit
        "RLL": (0.5,  .restorative),   // REM into light (normal ending)
        "RRR": (0.8,  .restorative),   // Sustained REM
        "DDD": (0.8,  .restorative),   // Sustained deep

        // Neutral — normal transitions
        "LLL": (0.1,  .neutral),       // Sustained light (not great, not bad)
        "LLR": (0.3,  .neutral),       // Light to REM
        "LRL": (0.4,  .neutral),       // Brief REM
        "RLD": (0.4,  .neutral),       // REM → light → deep (new cycle)
        "LRR": (0.5,  .neutral),       // Light into REM

        // Fragmented — awakenings mid-sleep
        "LWL": (-0.7, .fragmented),    // Microarousal in light sleep
        "DWL": (-0.6, .fragmented),    // Waking from deep (sleep inertia)
        "DWD": (-0.5, .fragmented),    // Brief awakening in deep
        "LWD": (-0.4, .fragmented),    // Awakening then back to deep
        "WLL": (0.2,  .neutral),       // Returning to sleep — positive recovery
        "WLD": (0.3,  .neutral),       // Returning to deep sleep — good recovery

        // Destructive — REM interruption, sustained wakefulness
        "RWL": (-1.0, .destructive),   // REM interrupted — worst pattern
        "RWR": (-0.9, .destructive),   // REM fragmentation
        "RWD": (-0.8, .destructive),   // REM broken into deep
        "WRW": (-0.9, .destructive),   // Isolated REM fragment
        "WWW": (-1.0, .destructive),   // Sustained insomnia
        "WWL": (-0.6, .destructive),   // Prolonged awakening
        "WLW": (-0.7, .destructive),   // Failed return to sleep
        "WDW": (-0.6, .destructive),   // Brief deep then awake again
        "WRL": (-0.5, .fragmented),    // Awakening into REM (unusual)
        "DWR": (-0.5, .fragmented),    // Deep broken, into REM
    ]

    // MARK: - Single Night Analysis

    /// Analyze one night's sleep phases as codons.
    ///
    /// - Parameter record: A SleepRecord with phase data.
    /// - Returns: CodonAnalysisResult, or nil if < 3 phases.
    public static func analyzeNight(_ record: SleepRecord) -> CodonAnalysisResult? {
        // Only analyze phases within sleep blocks (bedtime to wake).
        // Exclude extended wakefulness between split sleep blocks — that's
        // normal vigilia, not a disruption.
        let sleepPhases = record.phases.filter { phase in
            let h = phase.hour
            let bed = record.bedtimeHour
            let wake = record.wakeupHour
            if bed > wake {
                // Crosses midnight
                return h >= bed || h <= wake
            } else {
                return h >= bed && h <= wake
            }
        }
        let phases = sleepPhases.map { $0.phase }
        guard phases.count >= 3 else { return nil }

        // Check if we have real stage data (not just awake/light binary)
        let uniquePhases = Set(phases)
        let hasStageData = uniquePhases.count > 2 || uniquePhases.contains(.deep) || uniquePhases.contains(.rem)

        // Extract overlapping triplets
        var codons: [SleepCodon] = []
        for i in 0..<(phases.count - 2) {
            let triplet = [phases[i], phases[i + 1], phases[i + 2]]
            let code = triplet.map { phaseCode($0) }.joined()
            let (score, label) = codonScores[code] ?? (0.0, .neutral)
            codons.append(SleepCodon(phases: triplet, score: score, label: label))
        }

        guard !codons.isEmpty else { return nil }

        let restorative = codons.filter { $0.label == .restorative }.count
        let disruptive = codons.filter { $0.label == .fragmented || $0.label == .destructive }.count

        // Integrity = normalized sum of scores mapped to [0, 1]
        let totalScore = codons.reduce(0.0) { $0 + $1.score }
        let maxPossible = Double(codons.count)
        let integrity = (totalScore + maxPossible) / (2 * maxPossible) // maps [-max, max] → [0, 1]

        // Dominant codon
        var freq: [String: Int] = [:]
        for c in codons { freq[c.code, default: 0] += 1 }
        let dominant = freq.max(by: { $0.value < $1.value })?.key

        let worst = codons.min(by: { $0.score < $1.score })

        return CodonAnalysisResult(
            codons: codons,
            integrityScore: integrity,
            restorativeCount: restorative,
            disruptiveCount: disruptive,
            dominantCodon: dominant,
            worstCodon: worst,
            hasStageData: hasStageData
        )
    }

    // MARK: - Multi-Night Analysis

    /// Analyze codon patterns across multiple nights.
    ///
    /// - Parameter records: Sleep records (needs ≥ 7 with phase data).
    /// - Returns: MultiNightCodonResult, or nil if insufficient data.
    public static func analyzeMultiNight(records: [SleepRecord]) -> MultiNightCodonResult? {
        let results = records.compactMap { record -> NightCodonSummary? in
            guard let analysis = analyzeNight(record), analysis.hasStageData else { return nil }
            return NightCodonSummary(
                day: record.day,
                integrityScore: analysis.integrityScore,
                totalCodons: analysis.codons.count,
                disruptiveCount: analysis.disruptiveCount
            )
        }

        guard results.count >= 3 else { return nil }

        let meanIntegrity = results.map(\.integrityScore).reduce(0, +) / Double(results.count)

        // Most common disruption across all nights
        var disruptionFreq: [String: Int] = [:]
        for record in records {
            guard let analysis = analyzeNight(record) else { continue }
            for codon in analysis.codons where codon.label == .fragmented || codon.label == .destructive {
                disruptionFreq[codon.code, default: 0] += 1
            }
        }
        let mostCommon = disruptionFreq.max(by: { $0.value < $1.value })?.key

        // Trend: linear slope of integrity scores over time
        let trend: Double
        if results.count >= 3 {
            let x = results.enumerated().map { Double($0.offset) }
            let y = results.map(\.integrityScore)
            let n = Double(x.count)
            let sumX = x.reduce(0, +)
            let sumY = y.reduce(0, +)
            let sumXY = zip(x, y).map(*).reduce(0, +)
            let sumX2 = x.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            trend = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0
        } else {
            trend = 0
        }

        return MultiNightCodonResult(
            nightlyResults: results,
            meanIntegrity: meanIntegrity,
            mostCommonDisruption: mostCommon,
            trend: trend
        )
    }

    // MARK: - Helpers

    private static func phaseCode(_ phase: SleepPhase) -> String {
        switch phase {
        case .awake: return "W"
        case .light: return "L"
        case .deep:  return "D"
        case .rem:   return "R"
        }
    }
}
