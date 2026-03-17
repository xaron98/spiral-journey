import Foundation
import SwiftData
import SpiralKit

// MARK: - SDUserGoal

/// SwiftData model mirroring SpiralKit.SleepGoal.
@Model
final class SDUserGoal {

    // MARK: Persisted Properties

    @Attribute(.unique) var goalID: UUID
    /// Stored as CoachMode.rawValue ("generalHealth" | "shiftWork" | "customSchedule" | "rephase").
    var mode: String
    var targetBedHour: Double
    var targetWakeHour: Double
    var targetDuration: Double
    var toleranceMinutes: Double
    var allowsSplitSleep: Bool
    var rephaseStepMinutes: Double

    // MARK: Init

    init(
        goalID: UUID = UUID(),
        mode: String,
        targetBedHour: Double,
        targetWakeHour: Double,
        targetDuration: Double,
        toleranceMinutes: Double,
        allowsSplitSleep: Bool = false,
        rephaseStepMinutes: Double = 0
    ) {
        self.goalID = goalID
        self.mode = mode
        self.targetBedHour = targetBedHour
        self.targetWakeHour = targetWakeHour
        self.targetDuration = targetDuration
        self.toleranceMinutes = toleranceMinutes
        self.allowsSplitSleep = allowsSplitSleep
        self.rephaseStepMinutes = rephaseStepMinutes
    }

    // MARK: Converters

    /// Create an SDUserGoal from a SpiralKit SleepGoal.
    convenience init(from goal: SleepGoal) {
        self.init(
            mode: goal.mode.rawValue,
            targetBedHour: goal.targetBedHour,
            targetWakeHour: goal.targetWakeHour,
            targetDuration: goal.targetDuration,
            toleranceMinutes: goal.toleranceMinutes,
            allowsSplitSleep: goal.allowsSplitSleep,
            rephaseStepMinutes: goal.rephaseStepMinutes
        )
    }

    /// Convert back to a SpiralKit SleepGoal.
    func toSleepGoal() -> SleepGoal {
        SleepGoal(
            mode: CoachMode(rawValue: mode) ?? .generalHealth,
            targetBedHour: targetBedHour,
            targetWakeHour: targetWakeHour,
            targetDuration: targetDuration,
            toleranceMinutes: toleranceMinutes,
            allowsSplitSleep: allowsSplitSleep,
            rephaseStepMinutes: rephaseStepMinutes
        )
    }
}
