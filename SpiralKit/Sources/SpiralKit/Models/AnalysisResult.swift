import Foundation

/// Sleep statistics derived from all SleepRecords.
public struct SleepStats: Codable, Sendable {
    public var meanAcrophase: Double
    public var stdAcrophase: Double
    public var stdBedtime: Double       // circular SD of bedtimeHour in hours
    public var meanAmplitude: Double
    public var rhythmStability: Double  // 0-1
    public var socialJetlag: Double     // minutes
    public var weekdayAmp: Double
    public var weekendAmp: Double
    public var ampDrop: Double          // percent
    public var meanSleepDuration: Double
    public var meanR2: Double
    public var sri: Double              // Sleep Regularity Index 0-100

    public init(
        meanAcrophase: Double = 0, stdAcrophase: Double = 0,
        stdBedtime: Double = 0,
        meanAmplitude: Double = 0, rhythmStability: Double = 0,
        socialJetlag: Double = 0, weekdayAmp: Double = 0,
        weekendAmp: Double = 0, ampDrop: Double = 0,
        meanSleepDuration: Double = 0, meanR2: Double = 0,
        sri: Double = 0
    ) {
        self.meanAcrophase = meanAcrophase
        self.stdAcrophase = stdAcrophase
        self.stdBedtime = stdBedtime
        self.meanAmplitude = meanAmplitude
        self.rhythmStability = rhythmStability
        self.socialJetlag = socialJetlag
        self.weekdayAmp = weekdayAmp
        self.weekendAmp = weekendAmp
        self.ampDrop = ampDrop
        self.meanSleepDuration = meanSleepDuration
        self.meanR2 = meanR2
        self.sri = sri
    }
}

// MARK: - Localization Keys

/// Stable key used for the composite score label.
public enum ScoreLabel: String, Codable, Sendable, CaseIterable {
    case excellent        // ≥ 85
    case good             // ≥ 70
    case moderate         // ≥ 50
    case needsAttention   // < 50
}

/// Stable keys for category names.
public enum CategoryKey: String, Codable, Sendable, CaseIterable {
    case duration, regularity, rhythm, jetlag, pattern, timing
}

/// Stable keys for category detail text (maps to a localized string in the app).
public enum CategoryDetailKey: String, Codable, Sendable, CaseIterable {
    case noData
    case belowRecommended
    case excessive
    case healthy
    case veryConsistent
    case someVariability
    case highVariability
    case strongRhythm
    case moderateRhythm
    case weakRhythm
    case minimalJetlag
    case moderateJetlag
    case highJetlag
    case normalTiming
    case earlyTiming
    case lateTiming
    case patternInsufficient
}

/// Stable keys for trend label text.
public enum TrendKey: String, Codable, Sendable, CaseIterable {
    case rhythmStrength, sleepDuration, rhythmClarity, insufficientData
}

/// Stable keys for trend detail text.
public enum TrendDetailKey: String, Codable, Sendable, CaseIterable {
    case amplitudeUp, amplitudeDown, amplitudeStable
    case durationUp, durationDown, durationStable
    case r2Up, r2Down, r2Stable
    case needMoreDays
}

/// Stable keys for recommendation title + text.
public enum RecommendationKey: String, Codable, Sendable, CaseIterable {
    case increaseSleep
    case improveDuration
    case consistentSchedule
    case stabilizeSchedule
    case reduceSocialJetlag
    case minimizeWeekendLag
    case strengthenRhythm
    case reinforceZeitgebers
    case advancePhase
    case stabilizePeriod
    case structureRoutine
    case addressNegativeTrends
    case reviewStimulants
}

// MARK: - Model Structs

/// A single scored category in the conclusions report.
public struct CategoryScore: Codable, Identifiable, Sendable {
    public var id: String   // "duration", "regularity", "rhythm", "jetlag", "pattern", "timing"
    public var label: String
    public var value: String
    public var score: Int   // 0-100
    public var status: ScoreStatus
    public var detail: String
    /// Stable localization key — use this in the view layer instead of `label`.
    public var labelKey: CategoryKey?
    /// Stable localization key — use this in the view layer instead of `detail`.
    public var detailKey: CategoryDetailKey?
    /// Numeric args for detail string interpolation (order matches the key's format).
    public var detailArgs: [Double]

    public init(id: String, label: String, value: String, score: Int, status: ScoreStatus, detail: String,
                labelKey: CategoryKey? = nil, detailKey: CategoryDetailKey? = nil, detailArgs: [Double] = []) {
        self.id = id
        self.label = label
        self.value = value
        self.score = score
        self.status = status
        self.detail = detail
        self.labelKey = labelKey
        self.detailKey = detailKey
        self.detailArgs = detailArgs
    }
}

public enum ScoreStatus: String, Codable, Sendable {
    case good     = "good"
    case moderate = "moderate"
    case poor     = "poor"
}

/// Trend item (improving, deteriorating, or stable).
public struct TrendItem: Codable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var detail: String
    /// Stable localization keys.
    public var labelKey: TrendKey?
    public var detailKey: TrendDetailKey?
    public var detailArgs: [Double]

    public init(id: UUID = UUID(), label: String, detail: String,
                labelKey: TrendKey? = nil, detailKey: TrendDetailKey? = nil, detailArgs: [Double] = []) {
        self.id = id
        self.label = label
        self.detail = detail
        self.labelKey = labelKey
        self.detailKey = detailKey
        self.detailArgs = detailArgs
    }
}

/// Trend analysis comparing first half vs second half of data.
public struct TrendAnalysis: Codable, Sendable {
    public var improving: [TrendItem]
    public var deteriorating: [TrendItem]
    public var stable: [TrendItem]

    public init(improving: [TrendItem] = [], deteriorating: [TrendItem] = [], stable: [TrendItem] = []) {
        self.improving = improving
        self.deteriorating = deteriorating
        self.stable = stable
    }
}

/// A personalized recommendation.
public struct Recommendation: Codable, Identifiable, Sendable {
    public var id: UUID
    public var priority: Int  // 1 = most important
    public var title: String
    public var text: String
    /// Stable localization key.
    public var key: RecommendationKey?
    public var args: [Double]

    public init(id: UUID = UUID(), priority: Int, title: String, text: String,
                key: RecommendationKey? = nil, args: [Double] = []) {
        self.id = id
        self.priority = priority
        self.title = title
        self.text = text
        self.key = key
        self.args = args
    }
}

/// Full analysis snapshot for display and caching.
public struct AnalysisResult: Codable, Sendable {
    public var composite: Int
    public var label: String
    public var hexColor: String
    /// Stable localization key for the composite score label.
    public var scoreKey: ScoreLabel?
    public var categories: [CategoryScore]
    public var trends: TrendAnalysis
    public var recommendations: [Recommendation]
    public var signatures: [DisorderSignature]
    public var stats: SleepStats
    /// Spiral Consistency Score — pattern stability over the last 7 (or 30) nights.
    /// nil when there is insufficient data (< 2 nights with sleep).
    public var consistency: SpiralConsistencyScore?
    /// The single most important coaching insight for the current goal.
    /// nil when the analysis was produced without a SleepGoal (backward compatible).
    public var coachInsight: CoachInsight?

    public init(
        composite: Int = 0,
        label: String = "",
        hexColor: String = "#5bffa8",
        scoreKey: ScoreLabel? = nil,
        categories: [CategoryScore] = [],
        trends: TrendAnalysis = TrendAnalysis(),
        recommendations: [Recommendation] = [],
        signatures: [DisorderSignature] = [],
        stats: SleepStats = SleepStats(),
        consistency: SpiralConsistencyScore? = nil,
        coachInsight: CoachInsight? = nil
    ) {
        self.composite = composite
        self.label = label
        self.hexColor = hexColor
        self.scoreKey = scoreKey
        self.categories = categories
        self.trends = trends
        self.recommendations = recommendations
        self.signatures = signatures
        self.stats = stats
        self.consistency = consistency
        self.coachInsight = coachInsight
    }
}
