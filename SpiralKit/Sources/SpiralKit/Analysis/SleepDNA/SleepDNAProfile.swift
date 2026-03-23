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
    /// Persistent Circadian Homology: topological features of the helix point cloud.
    /// `nil` when tier is not `.full`.
    public let persistentHomology: PersistentHomologyResult?
    /// Linking Number Density between the two helix strands.
    /// `nil` when tier is not `.full`.
    public let linkingNumber: LinkingNumberResult?
    /// Windowed mutual information spectrum between circadian and homeostatic signals.
    /// `nil` when tier is not `.full` or insufficient data.
    public let mutualInfoSpectrum: MISResult?
    /// Helix Alignment Score: current week vs most similar historical week [0, 1].
    /// Close to 1 = very stable habit. `nil` when insufficient data.
    public let hasScore: Double?
    /// Helix Alignment Score: current week vs 4-week rolling baseline [0, 1].
    /// `nil` when fewer than 28 days of data are available.
    public let baselineHAS: Double?
    /// Poisson fragmentation analysis: models nightly awakenings as a Poisson process.
    /// `nil` when tier is below `.intermediate` (fewer than 4 weeks of data).
    public let poissonFragmentation: PoissonFragmentationResult?
    /// Hawkes event-impact analysis: temporal excitation of fragmentation by circadian events.
    /// `nil` when tier is not `.full` (fewer than 8 weeks of data).
    public let hawkesAnalysis: HawkesAnalysisResult?
    /// Intra-night codon analysis: sleep stage transition quality.
    /// `nil` when phase data is unavailable (no Apple Watch).
    public let codonAnalysis: SleepCodonAnalyzer.MultiNightCodonResult?
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
        persistentHomology: PersistentHomologyResult? = nil,
        linkingNumber: LinkingNumberResult? = nil,
        mutualInfoSpectrum: MISResult? = nil,
        hasScore: Double? = nil,
        baselineHAS: Double? = nil,
        poissonFragmentation: PoissonFragmentationResult? = nil,
        codonAnalysis: SleepCodonAnalyzer.MultiNightCodonResult? = nil,
        hawkesAnalysis: HawkesAnalysisResult? = nil,
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
        self.persistentHomology = persistentHomology
        self.linkingNumber = linkingNumber
        self.mutualInfoSpectrum = mutualInfoSpectrum
        self.hasScore = hasScore
        self.baselineHAS = baselineHAS
        self.poissonFragmentation = poissonFragmentation
        self.codonAnalysis = codonAnalysis
        self.hawkesAnalysis = hawkesAnalysis
        self.tier = tier
        self.computedAt = computedAt
        self.dataWeeks = dataWeeks
    }
}
