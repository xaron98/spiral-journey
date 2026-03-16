import Foundation

// MARK: - Coach Mode

/// The operational mode that determines how the coach evaluates sleep.
/// - generalHealth: Evaluates against standard circadian health baseline (23:00-07:00 ± 90 min).
/// - shiftWork: Evaluates against user-defined shift schedule; no normative judgment.
/// - customSchedule: Evaluates against any user-defined target schedule.
/// - rephase: Evaluates progress toward a phase-shift target.
public enum CoachMode: String, Codable, Sendable, CaseIterable {
    case generalHealth
    case shiftWork
    case customSchedule
    case rephase
}

// MARK: - Sleep Goal

/// Defines what "correct" sleep looks like for the user.
/// When mode == .generalHealth and no custom goal is set, the engine uses generalHealthDefault.
public struct SleepGoal: Codable, Sendable {
    /// The evaluation mode.
    public var mode: CoachMode

    /// Target bedtime as clock hour (0–24). e.g. 23.0 = 23:00.
    public var targetBedHour: Double

    /// Target wake time as clock hour (0–24). e.g. 7.0 = 07:00.
    public var targetWakeHour: Double

    /// Target sleep duration in hours (e.g. 8.0).
    public var targetDuration: Double

    /// Acceptable deviation before flagging an issue (minutes).
    /// Default 90 for generalHealth, 60 for shift/custom/rephase.
    public var toleranceMinutes: Double

    /// Whether a split-sleep pattern is acceptable for this goal.
    public var allowsSplitSleep: Bool

    /// For rephase mode: minutes to advance per day.
    /// Derived from RephaseIntensity.minutesPerDay; 0 for non-rephase modes.
    public var rephaseStepMinutes: Double

    public init(
        mode: CoachMode,
        targetBedHour: Double,
        targetWakeHour: Double,
        targetDuration: Double,
        toleranceMinutes: Double,
        allowsSplitSleep: Bool = false,
        rephaseStepMinutes: Double = 0
    ) {
        self.mode = mode
        self.targetBedHour = targetBedHour
        self.targetWakeHour = targetWakeHour
        self.targetDuration = targetDuration
        self.toleranceMinutes = toleranceMinutes
        self.allowsSplitSleep = allowsSplitSleep
        self.rephaseStepMinutes = rephaseStepMinutes
    }

    /// Standard general-health reference: bedtime 23:00, wake 07:00, 8 h, ±90 min tolerance.
    public static let generalHealthDefault = SleepGoal(
        mode: .generalHealth,
        targetBedHour: 23.0,
        targetWakeHour: 7.0,
        targetDuration: 8.0,
        toleranceMinutes: 90
    )

    /// Circular midpoint of the target sleep window (bed → wake arc).
    public var targetMidSleepHour: Double {
        CoachEngine.circularMidSleep(bed: targetBedHour, wake: targetWakeHour)
    }
}

// MARK: - Coach Issue Key

/// Stable localization key for each type of coaching issue.
/// The view layer maps these to `coach.issue.<key>.*` localization strings.
public enum CoachIssueKey: String, Codable, Sendable, CaseIterable {
    // General health issues
    case delayedPhase            // Sleep significantly later than reference
    case advancedPhase           // Sleep significantly earlier than reference
    case splitSleep              // Major daytime sleep block fragmenting the cycle
    case socialJetlag            // Large weekday–weekend midSleep difference
    case irregularSchedule       // High day-to-day variability
    case insufficientDuration    // Sleeping too little
    case fragmentedSleep         // Many awakenings within main sleep block
    case sufficientButMisaligned // Duration OK but timing is off
    case maintenance             // Everything within tolerance — keep it up

    // Shift work
    case offTargetForShift       // Actual sleep outside shift goal tolerances

    // Custom schedule
    case offTargetForCustomSchedule // Actual sleep outside custom goal tolerances

    // Rephase
    case rephaseInProgress       // Still meaningfully behind rephase target

    // Context block conflicts
    case sleepOverlapsContext        // Sleep physically overlaps a work/study block
    case sleepTooCloseToContext      // Wake-up is too close to a scheduled block
    case daytimeSleepConsumesContext // Significant daytime sleep falls within a scheduled block

    // Shift-specific context-aware coaching (evidence-informed)
    case shiftLightTiming            // Strategic bright-light timing during shift (g≈1.08)
    case sleepinessRiskDuringWork    // High Process S during scheduled work block (S/C misalignment)

    // Fallback
    case insufficientData        // Not enough records to evaluate
}

// MARK: - Coach Severity

/// Visual severity level for coloring the insight card.
public enum CoachSeverity: Int, Codable, Sendable, Comparable {
    case info     = 0   // Green  — maintenance or no data
    case mild     = 1   // Accent — small deviation, easy fix
    case moderate = 2   // Orange — meaningful issue worth addressing
    case urgent   = 3   // Red    — significant health/schedule risk

    public static func < (lhs: CoachSeverity, rhs: CoachSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Coach Insight

/// The single most important finding for the user right now.
/// Title + reason + action + expectedOutcome are English fallback strings.
/// The view layer should prefer `coach.issue.<issueKey>.*` localization keys.
public struct CoachInsight: Codable, Sendable {
    /// Stable key for localization lookup.
    public var issueKey: CoachIssueKey
    /// What is happening (headline, e.g. "Delayed sleep phase").
    public var title: String
    /// Why it matters (body, e.g. "Part of your sleep falls after 3am…").
    public var reason: String
    /// What to do today (e.g. "Get bright light at 13:30 for 20-30 min").
    public var action: String
    /// Expected result of the action (e.g. "Goal: shift bedtime 15 min earlier").
    public var expectedOutcome: String
    /// Severity for UI color mapping.
    public var severity: CoachSeverity
    /// Numeric arguments for localization format strings (order matches key's format spec).
    public var args: [Double]
    /// Pre-formatted string arguments for localization format strings that use %@ specifiers.
    /// e.g. ["07:30"] for a time that should appear verbatim in the localized string.
    public var stringArgs: [String]

    public init(
        issueKey: CoachIssueKey,
        title: String,
        reason: String,
        action: String,
        expectedOutcome: String,
        severity: CoachSeverity,
        args: [Double] = [],
        stringArgs: [String] = []
    ) {
        self.issueKey = issueKey
        self.title = title
        self.reason = reason
        self.action = action
        self.expectedOutcome = expectedOutcome
        self.severity = severity
        self.args = args
        self.stringArgs = stringArgs
    }
}

// MARK: - Rhythm and Alignment State

/// Day-to-day consistency of the sleep schedule.
public enum RhythmState: String, Codable, Sendable {
    case stable    // SD of bed/wake < 60 min
    case variable  // SD of bed/wake ≥ 60 min
}

/// How the actual sleep window aligns with the goal or circadian baseline.
public enum AlignmentState: String, Codable, Sendable {
    case aligned    // Within tolerance of goal
    case delayed    // Significantly later than goal
    case advanced   // Significantly earlier than goal
    case splitSleep // Main sleep block fragmented by significant daytime sleep
    case fragmented // Many wake-ups within the main sleep window
    case offTarget  // Outside the goal window (shift/custom schedule modes)
}

// MARK: - Circadian Assessment

/// Intermediate metrics computed by CoachEngine.assess().
/// Exposed publicly so tests can verify individual metrics independently of the full evaluation.
public struct CircadianAssessment: Codable, Sendable {
    /// Signed deviation of actual midSleep from goal midSleep (minutes). Positive = late.
    public var midSleepDeviationMinutes: Double
    /// Signed deviation of actual wake time from goal wake time (minutes). Positive = late.
    public var wakeDeviationMinutes: Double
    /// Signed deviation of actual bedtime from goal bedtime (minutes). Positive = late.
    public var bedDeviationMinutes: Double
    /// Standard deviation of bedtimes across records (minutes).
    public var bedtimeStdMinutes: Double
    /// Standard deviation of wake times across records (minutes).
    public var wakeStdMinutes: Double
    /// Social jetlag: difference in midSleep between weekdays and weekends (minutes).
    public var socialJetlagMinutes: Double
    /// Mean sleep duration across records (hours).
    public var meanDurationHours: Double
    /// Duration deficit vs goal: max(0, targetDuration - meanDuration) × 60 (minutes).
    public var durationDeficitMinutes: Double
    /// True if a significant daytime sleep block (≥60 min) was detected alongside main sleep.
    public var hasSplitSleep: Bool
    /// Estimated total daytime sleep minutes (sleep in 08:00–20:00 window).
    public var splitSleepDaytimeMinutes: Double
    /// Fragmentation score 0–100 (higher = more fragmented).
    /// Derived from hourlyActivity transitions within the main sleep window.
    public var fragmentationScore: Double
    /// Estimated main sleep start hour (0–24).
    public var mainSleepStartHour: Double
    /// Estimated main sleep end hour (0–24).
    public var mainSleepEndHour: Double
    /// Number of records used in the assessment.
    public var recordCount: Int

    /// Derived rhythm state: variable if bed or wake SD ≥ 60 min, otherwise stable.
    public var rhythmState: RhythmState {
        (bedtimeStdMinutes >= 60 || wakeStdMinutes >= 60) ? .variable : .stable
    }

    /// Derived alignment state based on the dominant issue detected.
    public var alignmentState: AlignmentState {
        if hasSplitSleep { return .splitSleep }
        if fragmentationScore > 35 { return .fragmented }
        if midSleepDeviationMinutes >= 90 { return .delayed }
        if midSleepDeviationMinutes <= -90 { return .advanced }
        let offTarget = abs(bedDeviationMinutes) > 60 || abs(wakeDeviationMinutes) > 60
        if offTarget { return .offTarget }
        return .aligned
    }

    public init(
        midSleepDeviationMinutes: Double = 0,
        wakeDeviationMinutes: Double = 0,
        bedDeviationMinutes: Double = 0,
        bedtimeStdMinutes: Double = 0,
        wakeStdMinutes: Double = 0,
        socialJetlagMinutes: Double = 0,
        meanDurationHours: Double = 0,
        durationDeficitMinutes: Double = 0,
        hasSplitSleep: Bool = false,
        splitSleepDaytimeMinutes: Double = 0,
        fragmentationScore: Double = 0,
        mainSleepStartHour: Double = 0,
        mainSleepEndHour: Double = 0,
        recordCount: Int = 0
    ) {
        self.midSleepDeviationMinutes = midSleepDeviationMinutes
        self.wakeDeviationMinutes = wakeDeviationMinutes
        self.bedDeviationMinutes = bedDeviationMinutes
        self.bedtimeStdMinutes = bedtimeStdMinutes
        self.wakeStdMinutes = wakeStdMinutes
        self.socialJetlagMinutes = socialJetlagMinutes
        self.meanDurationHours = meanDurationHours
        self.durationDeficitMinutes = durationDeficitMinutes
        self.hasSplitSleep = hasSplitSleep
        self.splitSleepDaytimeMinutes = splitSleepDaytimeMinutes
        self.fragmentationScore = fragmentationScore
        self.mainSleepStartHour = mainSleepStartHour
        self.mainSleepEndHour = mainSleepEndHour
        self.recordCount = recordCount
    }
}

// MARK: - Temporal Pattern

/// A recurring pattern detected by comparing per-weekday averages against the overall mean.
/// Example: "Mondays you go to bed 45 min later than average."
public struct TemporalPattern: Codable, Sendable, Identifiable {
    public var id: UUID
    /// ISO weekday: 1=Sunday … 7=Saturday
    public var weekday: Int
    /// Signed deviation from mean bedtime, in minutes. Positive = later.
    public var bedtimeDeviationMinutes: Double
    /// Signed deviation from mean wake time, in minutes. Positive = later.
    public var wakeDeviationMinutes: Double
    /// Signed deviation from mean duration, in minutes. Positive = longer.
    public var durationDeviationMinutes: Double
    /// Number of samples backing this pattern (to avoid spurious patterns from 1 data point).
    public var sampleCount: Int

    public init(
        id: UUID = UUID(),
        weekday: Int,
        bedtimeDeviationMinutes: Double,
        wakeDeviationMinutes: Double,
        durationDeviationMinutes: Double,
        sampleCount: Int
    ) {
        self.id = id
        self.weekday = weekday
        self.bedtimeDeviationMinutes = bedtimeDeviationMinutes
        self.wakeDeviationMinutes = wakeDeviationMinutes
        self.durationDeviationMinutes = durationDeviationMinutes
        self.sampleCount = sampleCount
    }

    /// Weekday abbreviation (localized via Calendar).
    public var weekdayName: String {
        let cal = Calendar.current
        // Calendar.shortWeekdaySymbols is 0-indexed (Sun=0) but our weekday is 1-indexed (Sun=1)
        return cal.shortWeekdaySymbols[weekday - 1]
    }

    /// True if the pattern is significant enough to display (≥2 samples, ≥30 min deviation).
    public var isSignificant: Bool {
        sampleCount >= 2 && (abs(bedtimeDeviationMinutes) >= 30 || abs(durationDeviationMinutes) >= 30)
    }
}

// MARK: - Progress Celebration

/// A positive event worth celebrating — SRI improved, streak hit, duration on target, etc.
public struct ProgressCelebration: Codable, Sendable, Identifiable {
    public var id: UUID
    public var type: CelebrationType
    /// Human-readable description (English fallback).
    public var message: String
    /// Localization key for view layer.
    public var messageKey: String
    /// Numeric args for the localized format (e.g. [5] for "5-day streak").
    public var args: [Double]

    public init(
        id: UUID = UUID(),
        type: CelebrationType,
        message: String,
        messageKey: String,
        args: [Double] = []
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.messageKey = messageKey
        self.args = args
    }

    public enum CelebrationType: String, Codable, Sendable {
        case sriImproved          // SRI went up ≥5 pts week-over-week
        case consistencyStreak    // N consecutive nights within goal
        case durationOnTarget     // Mean duration within ±30 min of goal for 7 days
        case bedtimeOnTarget      // Mean bedtime within tolerance for 7 days
        case bestWeekEver         // Composite score is highest so far
        case fragmentationDown    // Fragmentation score dropped ≥10 pts
    }
}

// MARK: - Micro-Habit

/// A small daily action derived from the current coach issue.
/// Cycles through 7 variants per issue so the user sees a fresh tip each day.
public struct MicroHabit: Codable, Sendable, Identifiable {
    public var id: UUID
    /// Which coach issue this micro-habit addresses.
    public var issueKey: CoachIssueKey
    /// Day within the 7-day cycle (0–6).
    public var cycleDay: Int
    /// Short action text (English fallback).
    public var action: String
    /// Localization key: "coach.microhabit.<issueKey>.<cycleDay>"
    public var actionKey: String
    /// Whether the user has checked this off today.
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        issueKey: CoachIssueKey,
        cycleDay: Int,
        action: String,
        actionKey: String,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.issueKey = issueKey
        self.cycleDay = cycleDay
        self.action = action
        self.actionKey = actionKey
        self.isCompleted = isCompleted
    }
}

// MARK: - Weekly Digest

/// Summary comparing this week (last 7 days) vs the previous week.
public struct WeeklyDigest: Codable, Sendable {
    /// Mean bedtime this week (clock hour).
    public var meanBedtime: Double
    /// Mean bedtime previous week (clock hour).
    public var prevMeanBedtime: Double

    /// Mean wake time this week (clock hour).
    public var meanWakeTime: Double
    /// Mean wake time previous week (clock hour).
    public var prevMeanWakeTime: Double

    /// Mean duration this week (hours).
    public var meanDuration: Double
    /// Mean duration previous week (hours).
    public var prevMeanDuration: Double

    /// SRI this week.
    public var sri: Double
    /// SRI previous week.
    public var prevSRI: Double

    /// Composite score this week.
    public var compositeScore: Int
    /// Composite score previous week.
    public var prevCompositeScore: Int

    /// Best day (weekday 1–7) by duration or alignment.
    public var bestDay: Int?
    /// Worst day (weekday 1–7) by duration or alignment.
    public var worstDay: Int?

    /// Number of records this week.
    public var thisWeekRecordCount: Int
    /// Number of records previous week.
    public var prevWeekRecordCount: Int

    public init(
        meanBedtime: Double = 0, prevMeanBedtime: Double = 0,
        meanWakeTime: Double = 0, prevMeanWakeTime: Double = 0,
        meanDuration: Double = 0, prevMeanDuration: Double = 0,
        sri: Double = 0, prevSRI: Double = 0,
        compositeScore: Int = 0, prevCompositeScore: Int = 0,
        bestDay: Int? = nil, worstDay: Int? = nil,
        thisWeekRecordCount: Int = 0, prevWeekRecordCount: Int = 0
    ) {
        self.meanBedtime = meanBedtime
        self.prevMeanBedtime = prevMeanBedtime
        self.meanWakeTime = meanWakeTime
        self.prevMeanWakeTime = prevMeanWakeTime
        self.meanDuration = meanDuration
        self.prevMeanDuration = prevMeanDuration
        self.sri = sri
        self.prevSRI = prevSRI
        self.compositeScore = compositeScore
        self.prevCompositeScore = prevCompositeScore
        self.bestDay = bestDay
        self.worstDay = worstDay
        self.thisWeekRecordCount = thisWeekRecordCount
        self.prevWeekRecordCount = prevWeekRecordCount
    }

    /// Delta in mean bedtime (minutes). Positive = later.
    public var bedtimeDeltaMinutes: Double { (meanBedtime - prevMeanBedtime) * 60 }
    /// Delta in mean duration (minutes). Positive = longer.
    public var durationDeltaMinutes: Double { (meanDuration - prevMeanDuration) * 60 }
    /// Delta in SRI (points). Positive = improvement.
    public var sriDelta: Double { sri - prevSRI }
    /// Delta in composite score (points). Positive = improvement.
    public var compositeDelta: Int { compositeScore - prevCompositeScore }

    /// True if we have enough data in both weeks to show meaningful comparison.
    public var isValid: Bool { thisWeekRecordCount >= 3 && prevWeekRecordCount >= 3 }
}

// MARK: - Streak Data

/// Consecutive nights where the user met their sleep goal.
public struct StreakData: Codable, Sendable, Identifiable {
    public var id: UUID
    /// Current consecutive nights within goal.
    public var currentStreak: Int
    /// All-time best streak.
    public var bestStreak: Int
    /// Date when the current streak started (nil if streak == 0).
    public var streakStartDate: Date?
    /// Date when the best streak was achieved.
    public var bestStreakDate: Date?

    public init(
        id: UUID = UUID(),
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        streakStartDate: Date? = nil,
        bestStreakDate: Date? = nil
    ) {
        self.id = id
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.streakStartDate = streakStartDate
        self.bestStreakDate = bestStreakDate
    }

    /// True if streak is worth displaying (≥2 consecutive nights).
    public var isActive: Bool { currentStreak >= 2 }
    /// True if current streak equals or exceeds the best ever.
    public var isNewRecord: Bool { currentStreak >= bestStreak && currentStreak >= 3 }
}

// MARK: - Event Acknowledgment

/// A note linking a recent circadian event to sleep quality.
/// Example: "Yesterday's exercise may have helped — you fell asleep 20 min earlier."
public struct EventAcknowledgment: Codable, Sendable, Identifiable {
    public var id: UUID
    /// The event type that was detected.
    public var eventType: EventType
    /// Observed effect on sleep (positive or negative).
    public var effect: EventEffect
    /// English fallback message.
    public var message: String
    /// Localization key.
    public var messageKey: String
    /// Numeric arguments for format string.
    public var args: [Double]

    public init(
        id: UUID = UUID(),
        eventType: EventType,
        effect: EventEffect,
        message: String,
        messageKey: String,
        args: [Double] = []
    ) {
        self.id = id
        self.eventType = eventType
        self.effect = effect
        self.message = message
        self.messageKey = messageKey
        self.args = args
    }

    public enum EventEffect: String, Codable, Sendable {
        case positive   // Event correlated with better sleep
        case negative   // Event correlated with worse sleep
        case neutral    // Event detected but no clear effect
    }
}

// MARK: - Enhanced Coach Result

/// Container for all enhanced coaching data produced by the engine.
/// The base `CoachInsight` remains the primary insight; this adds secondary coaching layers.
public struct EnhancedCoachResult: Codable, Sendable {
    /// The primary actionable insight (same as AnalysisResult.coachInsight).
    public var insight: CoachInsight?
    /// Recurring weekday patterns (e.g. "Mondays you sleep 45 min later").
    public var temporalPatterns: [TemporalPattern]
    /// Positive achievements worth celebrating.
    public var celebrations: [ProgressCelebration]
    /// Today's micro-habit suggestion.
    public var microHabit: MicroHabit?
    /// Weekly summary with deltas.
    public var weeklyDigest: WeeklyDigest?
    /// Current streak status.
    public var streak: StreakData
    /// Event-sleep correlations (e.g. "exercise helped last night").
    public var eventAcknowledgments: [EventAcknowledgment]

    public init(
        insight: CoachInsight? = nil,
        temporalPatterns: [TemporalPattern] = [],
        celebrations: [ProgressCelebration] = [],
        microHabit: MicroHabit? = nil,
        weeklyDigest: WeeklyDigest? = nil,
        streak: StreakData = StreakData(),
        eventAcknowledgments: [EventAcknowledgment] = []
    ) {
        self.insight = insight
        self.temporalPatterns = temporalPatterns
        self.celebrations = celebrations
        self.microHabit = microHabit
        self.weeklyDigest = weeklyDigest
        self.streak = streak
        self.eventAcknowledgments = eventAcknowledgments
    }
}
