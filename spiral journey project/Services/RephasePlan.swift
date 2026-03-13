import Foundation
import SpiralKit

// MARK: - Rephase Intensity

/// How aggressively to shift the circadian clock each day.
enum RephaseIntensity: String, Codable, CaseIterable {
    case suave  = "suave"   // gentle  — ~15 min/day
    case normal = "normal"  // normal  — ~30 min/day
    case firme  = "firme"   // firm    — ~45 min/day

    /// Minutes to advance (or delay) per day.
    var minutesPerDay: Double {
        switch self {
        case .suave:  return 15
        case .normal: return 30
        case .firme:  return 45
        }
    }

    func displayName(bundle: Bundle = .main) -> String {
        switch self {
        case .suave:  return NSLocalizedString("rephase.intensity.suave.name",  bundle: bundle, comment: "")
        case .normal: return NSLocalizedString("rephase.intensity.normal.name", bundle: bundle, comment: "")
        case .firme:  return NSLocalizedString("rephase.intensity.firme.name",  bundle: bundle, comment: "")
        }
    }

    func intensityDescription(bundle: Bundle = .main) -> String {
        switch self {
        case .suave:  return NSLocalizedString("rephase.intensity.suave.desc",  bundle: bundle, comment: "")
        case .normal: return NSLocalizedString("rephase.intensity.normal.desc", bundle: bundle, comment: "")
        case .firme:  return NSLocalizedString("rephase.intensity.firme.desc",  bundle: bundle, comment: "")
        }
    }
}

// MARK: - Rephase Plan

/// User-configured circadian readjustment plan.
struct RephasePlan: Codable {
    /// Whether rephase mode is active.
    var isEnabled: Bool = false

    /// Target wake-up time (hour 0-24, e.g. 7.5 = 07:30).
    var targetWakeHour: Double = 7.0

    /// Desired sleep duration in hours.
    var targetSleepDuration: Double = 8.0

    /// If false, bedtime is derived automatically (targetWakeHour - targetSleepDuration).
    /// If true, the user has set a manual bedtime override.
    var manualBedtimeEnabled: Bool = false

    /// Manual bedtime hour override (only used when manualBedtimeEnabled is true).
    var manualTargetBedHour: Double = 23.0

    /// How aggressively to shift the clock.
    var intensity: RephaseIntensity = .normal

    /// Derived target bedtime hour (auto or manual).
    var derivedTargetBedHour: Double {
        if manualBedtimeEnabled {
            return manualTargetBedHour
        }
        // Subtract duration from wake, wrapping around midnight if needed.
        return ((targetWakeHour - targetSleepDuration) + 24).truncatingRemainder(dividingBy: 24)
    }
}

// MARK: - SleepGoal Bridge

extension RephasePlan {
    /// Convert the active rephase plan into a `SleepGoal` for CoachEngine evaluation.
    func asSleepGoal() -> SleepGoal {
        SleepGoal(
            mode: .rephase,
            targetBedHour: derivedTargetBedHour,
            targetWakeHour: targetWakeHour,
            targetDuration: targetSleepDuration,
            toleranceMinutes: 60,
            rephaseStepMinutes: intensity.minutesPerDay
        )
    }
}

// MARK: - Rephase Calculator

/// Stateless calculator for rephase-mode metrics.
enum RephaseCalculator {

    // MARK: - Delay

    /// Circular difference (in minutes) between the user's current estimated sleep-onset
    /// and the target bedtime. Positive = user goes to sleep later than target (delayed).
    ///
    /// `currentBedHour` is estimated as `meanAcrophase - targetSleepDuration/2`
    /// because acrophase (peak activity) typically sits at the midpoint of the wake window.
    /// Estimated delay in minutes regardless of `isEnabled` — used for preview in editor.
    static func currentDelayMinutes(plan: RephasePlan, meanAcrophase: Double) -> Double {
        // Estimated current sleep onset from cosinor acrophase
        let estimatedBedHour = ((meanAcrophase - plan.targetSleepDuration / 2) + 48)
            .truncatingRemainder(dividingBy: 24)
        // Circular difference: how far ahead of target is current bedtime?
        return circularDiffHours(from: plan.derivedTargetBedHour, to: estimatedBedHour) * 60
    }

    /// Circular difference between current wake time and target wake time (minutes).
    /// Positive = user wakes up later than target.
    static func wakeDelayMinutes(plan: RephasePlan, meanWakeHour: Double) -> Double {
        return circularDiffHours(from: plan.targetWakeHour, to: meanWakeHour) * 60
    }

    // MARK: - Daily adjustment

    /// Number of minutes to advance today to stay on the rephase schedule.
    /// Returns the intensity step, capped to remaining delay.
    static func dailyAdjustmentMinutes(plan: RephasePlan, meanAcrophase: Double) -> Double {
        let delay = currentDelayMinutes(plan: plan, meanAcrophase: meanAcrophase)
        guard delay > 0 else { return 0 }
        return min(plan.intensity.minutesPerDay, delay)
    }

    // MARK: - ETA

    /// Estimated nights remaining to reach the target, or nil if already on target.
    static func estimatedNightsToGoal(plan: RephasePlan, meanAcrophase: Double) -> Int? {
        let delay = currentDelayMinutes(plan: plan, meanAcrophase: meanAcrophase)
        guard delay > 1 else { return nil } // already there (within 1 min)
        let nights = Int(ceil(delay / plan.intensity.minutesPerDay))
        return nights
    }

    // MARK: - Display strings

    /// Short status string for the pill, e.g. "+2h 05m delayed" or "On target".
    static func delayString(plan: RephasePlan, meanAcrophase: Double, bundle: Bundle = .main) -> String {
        guard plan.isEnabled, meanAcrophase > 0 else { return "" }
        let delay = currentDelayMinutes(plan: plan, meanAcrophase: meanAcrophase)
        if abs(delay) < 5 { return NSLocalizedString("rephase.delay.onTarget", bundle: bundle, comment: "") }
        let sign  = delay > 0 ? "+" : "-"
        let mins  = abs(Int(delay.rounded()))
        let h     = mins / 60
        let m     = mins % 60
        let label = delay > 0
            ? NSLocalizedString("rephase.delay.late",  bundle: bundle, comment: "")
            : NSLocalizedString("rephase.delay.early", bundle: bundle, comment: "")
        if h > 0 {
            return "\(sign)\(h)h \(String(format: "%02d", m))m \(label)"
        } else {
            return "\(sign)\(m)m \(label)"
        }
    }

    /// Today's action string, e.g. "Advance 30 min tonight".
    static func todayActionText(plan: RephasePlan, meanAcrophase: Double, bundle: Bundle = .main) -> String {
        let adj = dailyAdjustmentMinutes(plan: plan, meanAcrophase: meanAcrophase)
        if adj < 1 { return NSLocalizedString("rephase.action.maintain", bundle: bundle, comment: "") }
        let mins = Int(adj.rounded())
        return String(format: NSLocalizedString("rephase.action.advance", bundle: bundle, comment: ""), mins)
    }

    /// Target wake time formatted as HH:mm string.
    static func formattedTargetWake(_ plan: RephasePlan) -> String {
        formatHour(plan.targetWakeHour)
    }

    /// Target bed time formatted as HH:mm string.
    static func formattedTargetBed(_ plan: RephasePlan) -> String {
        formatHour(plan.derivedTargetBedHour)
    }

    // MARK: - Private helpers

    /// Circular difference (hours) from `a` to `b`, in range (-12, +12].
    /// Positive = b is later than a on the 24-hour clock.
    private static func circularDiffHours(from a: Double, to b: Double) -> Double {
        var diff = (b - a).truncatingRemainder(dividingBy: 24)
        if diff > 12 { diff -= 24 }
        if diff <= -12 { diff += 24 }
        return diff
    }

    static func formatHour(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = (total / 60) % 24
        let mm = total % 60
        return String(format: "%02d:%02d", hh, mm)
    }
}
