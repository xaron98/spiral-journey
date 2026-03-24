import Foundation

/// Assembles a DayHealthProfile from raw HealthKit data.
/// Computes activityCosinor from hourly steps using existing CosinorAnalysis.
public enum DayHealthProfileBuilder {

    /// Build a complete day health profile from fetched HealthKit values.
    ///
    /// - Parameters:
    ///   - day: Day index (same as SleepRecord.day).
    ///   - date: Calendar date.
    ///   - hourlySteps: 24 values (raw step counts per hour).
    ///   - totalSteps: Total steps for the day.
    ///   - exerciseMinutes: Apple Exercise ring minutes.
    ///   - activeCalories: Active energy burned (kcal).
    ///   - restingHR: Resting heart rate (bpm), nil if unavailable.
    ///   - avgNocturnalHRV: Mean nocturnal HRV SDNN (ms), nil if unavailable.
    ///   - hrNadirHour: Hour of minimum heart rate, nil if unavailable.
    ///   - wristTempDeviation: Wrist temperature deviation (°C), nil if unavailable.
    ///   - daylightMinutes: Time in daylight (minutes), nil if unavailable.
    ///   - menstrualFlow: Flow level (0=none, 1=light, 2=medium, 3=heavy), nil if not tracked.
    /// - Returns: A fully assembled DayHealthProfile.
    public static func build(
        day: Int,
        date: Date,
        hourlySteps: [Double],
        totalSteps: Int,
        exerciseMinutes: Double,
        activeCalories: Double,
        restingHR: Double?,
        avgNocturnalHRV: Double?,
        hrNadirHour: Double?,
        wristTempDeviation: Double?,
        daylightMinutes: Double?,
        menstrualFlow: Int?
    ) -> DayHealthProfile {

        // Normalize hourly steps to 0-1 (2000 steps/hour ≈ active walking)
        let normalized = hourlySteps.map { min(1.0, $0 / 2000.0) }

        // Compute cosinor from hourly activity (24 data points)
        let activityCosinor: CosinorResult?
        if normalized.contains(where: { $0 > 0 }) {
            let hourlyActivity = normalized.enumerated().map { (hour, activity) in
                HourlyActivity(hour: hour, activity: activity)
            }
            activityCosinor = CosinorAnalysis.fit(hourlyActivity)
        } else {
            activityCosinor = nil
        }

        return DayHealthProfile(
            day: day,
            date: date,
            hourlySteps: normalized,
            totalSteps: totalSteps,
            exerciseMinutes: exerciseMinutes,
            activeCalories: activeCalories,
            restingHR: restingHR,
            avgNocturnalHRV: avgNocturnalHRV,
            hrNadirHour: hrNadirHour,
            wristTempDeviation: wristTempDeviation,
            daylightMinutes: daylightMinutes,
            menstrualFlow: menstrualFlow,
            activityCosinor: activityCosinor
        )
    }
}
