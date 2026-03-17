import Foundation

// MARK: - Analysis Tier

/// Data sufficiency tier that determines which pipeline stages run.
public enum AnalysisTier: String, Codable, Sendable {
    /// Fewer than 4 weeks of data. Basic encoding only.
    case basic
    /// 4-8 weeks. Adds sequence alignment predictions.
    case intermediate
    /// 8+ weeks. Full pipeline including motif discovery and mutation classification.
    case full
}

// MARK: - Week Cluster

/// A group of similar weeks discovered by motif-based clustering.
public struct WeekCluster: Identifiable, Codable, Sendable {
    public let id: UUID
    /// Human-readable label for this cluster (e.g. "Good-sleep weeks").
    public let label: String
    /// Indices of the member weeks in the original sequence array.
    public let memberWeekIndices: [Int]
    /// Mean sleep quality across all member weeks.
    public let avgQuality: Double

    public init(id: UUID = UUID(), label: String, memberWeekIndices: [Int], avgQuality: Double) {
        self.id = id
        self.label = label
        self.memberWeekIndices = memberWeekIndices
        self.avgQuality = avgQuality
    }
}

// MARK: - SleepDNA Profile

/// Consolidated output of the full SleepDNA analysis pipeline.
///
/// Aggregates nucleotides, sequences, synchrony measurements, motifs,
/// mutations, expression rules, alignment predictions, health markers,
/// and helix geometry into a single archivable snapshot.
public struct SleepDNAProfile: Codable, Sendable {
    /// Per-day 16-feature vectors.
    public let nucleotides: [DayNucleotide]
    /// Sliding-window week sequences.
    public let sequences: [WeekSequence]
    /// Phase-locking synchrony between sleep and context features.
    public let basePairs: [BasePairSynchrony]
    /// Recurring weekly sleep patterns.
    public let motifs: [SleepMotif]
    /// Per-week quality deviations from motif expectations.
    public let mutations: [SleepMutation]
    /// Cluster groupings of similar weeks.
    public let clusters: [WeekCluster]
    /// Context feature modulation rules.
    public let expressionRules: [ExpressionRule]
    /// DTW alignments of the current partial week against history.
    public let alignments: [WeekAlignment]
    /// Predicted tonight's sleep from sequence alignment, if available.
    public let prediction: SequencePrediction?
    /// Learned per-feature importance weights.
    public let scoringMatrix: SleepBLOSUM
    /// Health markers and alerts from the last 14 days.
    public let healthMarkers: HealthMarkers
    /// Per-day double-helix visualization parameters.
    public let helixGeometry: [DayHelixParams]
    /// Helix Alignment Score: current week vs most similar historical week [0, 1].
    /// Close to 1 = very stable habit. `nil` when insufficient data.
    public let hasScore: Double?
    /// Helix Alignment Score: current week vs 4-week rolling baseline [0, 1].
    /// `nil` when fewer than 28 days of data are available.
    public let baselineHAS: Double?
    /// Data sufficiency tier that was used for this computation.
    public let tier: AnalysisTier
    /// When this profile was computed.
    public let computedAt: Date
    /// Number of full weeks of data available.
    public let dataWeeks: Int

    public init(
        nucleotides: [DayNucleotide],
        sequences: [WeekSequence],
        basePairs: [BasePairSynchrony],
        motifs: [SleepMotif],
        mutations: [SleepMutation],
        clusters: [WeekCluster],
        expressionRules: [ExpressionRule],
        alignments: [WeekAlignment],
        prediction: SequencePrediction?,
        scoringMatrix: SleepBLOSUM,
        healthMarkers: HealthMarkers,
        helixGeometry: [DayHelixParams],
        hasScore: Double? = nil,
        baselineHAS: Double? = nil,
        tier: AnalysisTier,
        computedAt: Date,
        dataWeeks: Int
    ) {
        self.nucleotides = nucleotides
        self.sequences = sequences
        self.basePairs = basePairs
        self.motifs = motifs
        self.mutations = mutations
        self.clusters = clusters
        self.expressionRules = expressionRules
        self.alignments = alignments
        self.prediction = prediction
        self.scoringMatrix = scoringMatrix
        self.healthMarkers = healthMarkers
        self.helixGeometry = helixGeometry
        self.hasScore = hasScore
        self.baselineHAS = baselineHAS
        self.tier = tier
        self.computedAt = computedAt
        self.dataWeeks = dataWeeks
    }
}
