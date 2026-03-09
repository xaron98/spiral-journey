import Foundation

// MARK: - Disruption Classification

/// Classifies how a sleep pattern is disrupted.
public enum PatternDisruptionType: String, Codable, Sendable, CaseIterable {
    case none    // pattern is stable
    case local   // anomaly concentrated in ≤25% of the night arc
    case global  // entire pattern shifted or structurally different
    case mixed   // both local and global anomalies present
}

// MARK: - Pattern Insight

/// A single detected insight about a night or time window.
public struct PatternInsight: Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: PatternDisruptionType
    /// Short title shown in the card (e.g. "Disrupción localizada").
    public var title: String
    /// One-sentence summary suitable for the app coach card.
    public var summary: String
    /// 0 = informational, 1 = mild, 2 = moderate, 3 = high
    public var severity: Int
    /// Optional time window in clock hours that the insight covers (e.g. 3.0...4.5).
    public var affectedStart: Double?
    public var affectedEnd: Double?
    /// Actionable recommendation text.
    public var recommendedAction: String

    public init(
        id: UUID = UUID(),
        type: PatternDisruptionType,
        title: String,
        summary: String,
        severity: Int,
        affectedStart: Double? = nil,
        affectedEnd: Double? = nil,
        recommendedAction: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.severity = severity
        self.affectedStart = affectedStart
        self.affectedEnd = affectedEnd
        self.recommendedAction = recommendedAction
    }
}

// MARK: - Consistency Breakdown

/// Sub-metric contributions to the SpiralConsistencyScore.
public struct ConsistencyBreakdown: Codable, Sendable {
    /// Regularity of sleep-onset time (0-100). Weight 30%.
    public var sleepOnsetRegularity: Double
    /// Regularity of wake time (0-100). Weight 25%.
    public var wakeTimeRegularity: Double
    /// Similarity of fragmentation pattern across nights (0-100). Weight 25%.
    public var fragmentationPatternSimilarity: Double
    /// Stability of total sleep duration (0-100). Weight 10%.
    public var sleepDurationStability: Double
    /// Stability of recovery proxy: HR/HRV if available, cosinor R² otherwise (0-100). Weight 10%.
    public var recoveryStability: Double
    /// Whether recoveryStability was computed from real physiological data.
    public var recoveryFromRealData: Bool

    public init(
        sleepOnsetRegularity: Double = 0,
        wakeTimeRegularity: Double = 0,
        fragmentationPatternSimilarity: Double = 0,
        sleepDurationStability: Double = 0,
        recoveryStability: Double = 0,
        recoveryFromRealData: Bool = false
    ) {
        self.sleepOnsetRegularity    = sleepOnsetRegularity
        self.wakeTimeRegularity      = wakeTimeRegularity
        self.fragmentationPatternSimilarity = fragmentationPatternSimilarity
        self.sleepDurationStability  = sleepDurationStability
        self.recoveryStability       = recoveryStability
        self.recoveryFromRealData    = recoveryFromRealData
    }
}

// MARK: - Spiral Consistency Score

/// Main consistency metric (0-100) derived from the last 7 or 30 nights.
public struct SpiralConsistencyScore: Codable, Sendable {
    /// Final weighted score, 0-100.
    public var score: Int
    /// Human-readable label.
    public var label: ConsistencyLabel
    /// Breakdown of the five sub-metrics.
    public var breakdown: ConsistencyBreakdown
    /// Delta vs the previous equivalent window (positive = improving).
    public var deltaVsPreviousWeek: Double?
    /// Number of nights used in the calculation.
    public var nightsUsed: Int
    /// How confident is this score given data quantity and quality.
    public var confidence: ConfidenceLevel
    /// Detected insights (disruptions, shifts, etc.) ordered by severity desc.
    public var insights: [PatternInsight]
    /// Day indices (0-based) where a local disruption was detected.
    public var localDisruptionDays: [Int]
    /// Day indices where a global shift was detected.
    public var globalShiftDays: [Int]

    public init(
        score: Int = 0,
        label: ConsistencyLabel = .insufficient,
        breakdown: ConsistencyBreakdown = ConsistencyBreakdown(),
        deltaVsPreviousWeek: Double? = nil,
        nightsUsed: Int = 0,
        confidence: ConfidenceLevel = .low,
        insights: [PatternInsight] = [],
        localDisruptionDays: [Int] = [],
        globalShiftDays: [Int] = []
    ) {
        self.score                = score
        self.label                = label
        self.breakdown            = breakdown
        self.deltaVsPreviousWeek  = deltaVsPreviousWeek
        self.nightsUsed           = nightsUsed
        self.confidence           = confidence
        self.insights             = insights
        self.localDisruptionDays  = localDisruptionDays
        self.globalShiftDays      = globalShiftDays
    }
}

// MARK: - Supporting Enums

public enum ConsistencyLabel: String, Codable, Sendable, CaseIterable {
    case veryStable      // 85-100
    case stable          // 70-84
    case variable        // 50-69
    case disorganized    // <50
    case insufficient    // not enough data

    public var displayText: String {
        switch self {
        case .veryStable:   return "Muy estable"
        case .stable:       return "Estable"
        case .variable:     return "Variable"
        case .disorganized: return "Desorganizado"
        case .insufficient: return "Sin datos"
        }
    }

    /// Hex color matching severity (reuses app palette).
    public var hexColor: String {
        switch self {
        case .veryStable:   return "5bffa8"
        case .stable:       return "5bffa8"
        case .variable:     return "f5c842"
        case .disorganized: return "f05050"
        case .insufficient: return "555566"
        }
    }

    public static func from(score: Int) -> ConsistencyLabel {
        switch score {
        case 85...: return .veryStable
        case 70...: return .stable
        case 50...: return .variable
        default:    return .disorganized
        }
    }
}

public enum ConfidenceLevel: String, Codable, Sendable {
    case low      // < 4 nights
    case medium   // 4-6 nights
    case high     // ≥ 7 nights
}
