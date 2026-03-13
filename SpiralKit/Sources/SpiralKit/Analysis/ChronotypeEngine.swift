import Foundation

/// Scoring engine for the reduced Morningness-Eveningness Questionnaire (MEQ-5).
///
/// The MEQ-5 consists of 5 questions, each scored 1–5.
/// Total score range: 5–25 (minimum 5 since each question has min 1).
///
/// Questions (Adan & Almirall, 1991):
/// 1. What time would you get up if entirely free to plan your day?
/// 2. What time would you go to bed if entirely free to plan your evening?
/// 3. How alert do you feel during the first half hour after waking?
/// 4. At what time of day do you feel your best?
/// 5. One hears of "morning" and "evening" types. Which do you consider yourself to be?
///
/// Higher score → more morning-type. Lower score → more evening-type.
public enum ChronotypeEngine {

    // MARK: - Scoring

    /// Score a completed questionnaire.
    ///
    /// - Parameter answers: Array of exactly 5 integers (each 1–5).
    /// - Returns: Scored result with chronotype classification, or nil if input is invalid.
    public static func score(answers: [Int]) -> ChronotypeResult? {
        guard answers.count == 5 else { return nil }
        guard answers.allSatisfy({ (1...5).contains($0) }) else { return nil }

        let total = answers.reduce(0, +)
        let chronotype = Chronotype.from(score: total)

        return ChronotypeResult(
            answers: answers,
            totalScore: total,
            chronotype: chronotype,
            completedAt: Date()
        )
    }

    // MARK: - Goal Adjustment

    /// Adjust a sleep goal based on the user's chronotype.
    ///
    /// Shifts targetBedHour/targetWakeHour and tolerance based on chronotype.
    /// Only adjusts generalHealth mode goals — custom/shift/rephase goals
    /// reflect the user's chosen targets, not biological preference.
    ///
    /// - Parameters:
    ///   - base: The current sleep goal.
    ///   - chronotype: The user's determined chronotype.
    /// - Returns: Adjusted goal with personalized timing.
    public static func adjustedSleepGoal(base: SleepGoal, chronotype: Chronotype) -> SleepGoal {
        guard base.mode == .generalHealth else { return base }

        let bed: Double
        let wake: Double
        let tolerance: Double

        switch chronotype {
        case .definiteMorning:
            bed = 21.5    // 21:30
            wake = 5.5    // 05:30
            tolerance = 120  // Wider tolerance for extreme chronotypes
        case .moderateMorning:
            bed = 22.5    // 22:30
            wake = 6.5    // 06:30
            tolerance = 90
        case .intermediate:
            bed = 23.0    // 23:00
            wake = 7.0    // 07:00
            tolerance = 90
        case .moderateEvening:
            bed = 0.0     // 00:00
            wake = 8.0    // 08:00
            tolerance = 90
        case .definiteEvening:
            bed = 1.0     // 01:00
            wake = 9.0    // 09:00
            tolerance = 120  // Wider tolerance for extreme chronotypes
        }

        return SleepGoal(
            mode: base.mode,
            targetBedHour: bed,
            targetWakeHour: wake,
            targetDuration: base.targetDuration,
            toleranceMinutes: tolerance,
            allowsSplitSleep: base.allowsSplitSleep,
            rephaseStepMinutes: base.rephaseStepMinutes
        )
    }

    // MARK: - Tolerance check

    /// Check if a given bedtime is within reasonable range for a chronotype.
    /// Used by CoachEngine to avoid flagging "delayed" for someone who is naturally late.
    ///
    /// - Parameters:
    ///   - bedtime: Actual bedtime (clock hour, 0–24).
    ///   - chronotype: User's chronotype.
    /// - Returns: True if the bedtime is within the chronotype's normal range ± tolerance.
    public static func isWithinChronotypeRange(bedtime: Double, chronotype: Chronotype) -> Bool {
        let (lo, hi) = chronotype.idealBedRange
        let tolerance = 1.5  // ±1.5h outside ideal range is still "normal" for that chronotype

        // Handle midnight crossing
        let normalizedBed = bedtime < 12 ? bedtime + 24 : bedtime
        let normalizedLo = lo < 12 ? lo + 24 : lo
        let normalizedHi = hi < 12 ? hi + 24 : hi

        return normalizedBed >= (normalizedLo - tolerance) &&
               normalizedBed <= (normalizedHi + tolerance)
    }
}
