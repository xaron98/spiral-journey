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

    public init(
        issueKey: CoachIssueKey,
        title: String,
        reason: String,
        action: String,
        expectedOutcome: String,
        severity: CoachSeverity,
        args: [Double] = []
    ) {
        self.issueKey = issueKey
        self.title = title
        self.reason = reason
        self.action = action
        self.expectedOutcome = expectedOutcome
        self.severity = severity
        self.args = args
    }
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
