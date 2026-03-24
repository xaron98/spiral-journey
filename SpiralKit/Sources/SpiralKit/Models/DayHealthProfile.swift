import Foundation

/// Complete 24-hour health profile for one day.
/// Combines sleep data with fitness, cardio, temperature, and environmental data.
/// Transforms the app from a sleep tracker to a personal chronobiograph.
public struct DayHealthProfile: Codable, Sendable {

    /// Day index (same as SleepRecord.day).
    public let day: Int
    /// Calendar date of this day.
    public let date: Date

    // MARK: - Activity (diurnal signal for cosinor)

    /// Steps per hour (24 values, normalized to 0-1 where 1 ≈ 2000 steps/hour).
    public let hourlySteps: [Double]
    /// Total steps for the day.
    public let totalSteps: Int
    /// Minutes of exercise (Apple Exercise ring).
    public let exerciseMinutes: Double
    /// Active calories burned.
    public let activeCalories: Double

    // MARK: - Cardio

    /// Resting heart rate for the day (bpm). Nil if unavailable.
    public let restingHR: Double?
    /// Average nocturnal HRV (SDNN in ms). Nil if unavailable.
    public let avgNocturnalHRV: Double?
    /// Hour of day when heart rate was lowest (proxy for circadian nadir).
    public let hrNadirHour: Double?

    // MARK: - Temperature

    /// Wrist temperature deviation from baseline (°C). Nil if unavailable.
    /// Inverse proxy for core temperature nadir (correlation r=0.79).
    public let wristTempDeviation: Double?

    // MARK: - Environment

    /// Minutes spent in daylight (iOS 17+). Nil if unavailable.
    public let daylightMinutes: Double?

    // MARK: - Menstrual Cycle

    /// Menstrual flow level: 0=none, 1=light, 2=medium, 3=heavy. Nil if not tracked.
    public let menstrualFlow: Int?

    // MARK: - Computed

    /// Cosinor fit computed from hourly steps (circadian activity rhythm).
    public let activityCosinor: CosinorResult?

    // MARK: - Init

    public init(
        day: Int,
        date: Date,
        hourlySteps: [Double] = Array(repeating: 0, count: 24),
        totalSteps: Int = 0,
        exerciseMinutes: Double = 0,
        activeCalories: Double = 0,
        restingHR: Double? = nil,
        avgNocturnalHRV: Double? = nil,
        hrNadirHour: Double? = nil,
        wristTempDeviation: Double? = nil,
        daylightMinutes: Double? = nil,
        menstrualFlow: Int? = nil,
        activityCosinor: CosinorResult? = nil
    ) {
        self.day = day
        self.date = date
        self.hourlySteps = hourlySteps
        self.totalSteps = totalSteps
        self.exerciseMinutes = exerciseMinutes
        self.activeCalories = activeCalories
        self.restingHR = restingHR
        self.avgNocturnalHRV = avgNocturnalHRV
        self.hrNadirHour = hrNadirHour
        self.wristTempDeviation = wristTempDeviation
        self.daylightMinutes = daylightMinutes
        self.menstrualFlow = menstrualFlow
        self.activityCosinor = activityCosinor
    }
}
