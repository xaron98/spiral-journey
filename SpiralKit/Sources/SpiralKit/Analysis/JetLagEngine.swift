import Foundation

/// Generates multi-day jet lag adaptation plans using Phase Response Curves.
///
/// Core principle: use bright light to advance (eastward) or delay (westward)
/// the circadian clock, supplemented by melatonin and meal timing.
///
/// Phase shift rates from literature:
///   - Eastward (advance): ~1h/day maximum
///   - Westward (delay): ~1.5h/day maximum
///
/// References:
///   - Eastman & Burgess (2009). How to travel the world without jet lag.
///   - Waterhouse et al. (2007). Jet lag: trends and coping strategies. Lancet.
public enum JetLagEngine {

    // MARK: - Configuration

    /// Maximum phase advance per day (hours) — eastward.
    private static let maxAdvancePerDay = 1.0
    /// Maximum phase delay per day (hours) — westward.
    private static let maxDelayPerDay = 1.5
    /// Pre-travel adjustment days.
    private static let preTravelDays = 3

    // MARK: - Public API

    /// Generate a complete jet lag adaptation plan.
    ///
    /// - Parameters:
    ///   - offset: Timezone offset in hours (-12 to +12). Positive = east.
    ///   - travelDate: Date of travel departure.
    ///   - currentBedtime: User's current habitual bedtime (clock hour).
    ///   - currentWake: User's current habitual wake time (clock hour).
    /// - Returns: A JetLagPlan with day-by-day recommendations.
    public static func generatePlan(
        offset: Int,
        travelDate: Date,
        currentBedtime: Double,
        currentWake: Double
    ) -> JetLagPlan {
        let clampedOffset = max(-12, min(12, offset))
        guard clampedOffset != 0 else {
            return JetLagPlan(
                timezoneOffsetHours: 0,
                travelDate: travelDate,
                direction: .east,
                days: [],
                estimatedAdaptationDays: 0
            )
        }

        // Determine direction: for offsets > 8h east, it's faster to delay (go west)
        let direction: JetLagPlan.Direction
        let effectiveShift: Double

        if clampedOffset > 0 {
            if clampedOffset <= 8 {
                direction = .east
                effectiveShift = Double(clampedOffset)
            } else {
                // Faster to delay through the other direction
                direction = .west
                effectiveShift = Double(24 - clampedOffset)
            }
        } else {
            if clampedOffset >= -8 {
                direction = .west
                effectiveShift = Double(abs(clampedOffset))
            } else {
                direction = .east
                effectiveShift = Double(24 + clampedOffset)
            }
        }

        let ratePerDay = direction == .east ? maxAdvancePerDay : maxDelayPerDay
        let totalAdaptDays = Int(ceil(effectiveShift / ratePerDay))

        // Build days: pre-travel (-3 to -1) + travel (0) + post-travel (1 to adaptDays)
        var days: [JetLagDay] = []

        // Pre-travel days: start shifting up to 3 days before
        let preShiftDays = min(preTravelDays, totalAdaptDays)
        for i in (1...preShiftDays).reversed() {
            let dayOffset = -i
            let shiftSoFar = ratePerDay * Double(preShiftDays - i + 1)
            let day = buildDay(
                dayOffset: dayOffset,
                direction: direction,
                shiftSoFar: shiftSoFar,
                currentBedtime: currentBedtime,
                currentWake: currentWake
            )
            days.append(day)
        }

        // Travel day (0) and post-travel days
        let remainingShift = effectiveShift - (ratePerDay * Double(preShiftDays))
        let postDays = max(0, Int(ceil(remainingShift / ratePerDay)))

        for i in 0...(postDays) {
            let shiftSoFar = ratePerDay * Double(preShiftDays + i)
            let clamped = min(shiftSoFar, effectiveShift)
            let day = buildDay(
                dayOffset: i,
                direction: direction,
                shiftSoFar: clamped,
                currentBedtime: currentBedtime,
                currentWake: currentWake
            )
            days.append(day)
        }

        return JetLagPlan(
            timezoneOffsetHours: clampedOffset,
            travelDate: travelDate,
            direction: direction,
            days: days,
            estimatedAdaptationDays: totalAdaptDays
        )
    }

    // MARK: - Day Builder

    private static func buildDay(
        dayOffset: Int,
        direction: JetLagPlan.Direction,
        shiftSoFar: Double,
        currentBedtime: Double,
        currentWake: Double
    ) -> JetLagDay {
        let signedShift = direction == .east ? -shiftSoFar : shiftSoFar

        // Target bed/wake adjusted by cumulative shift
        let targetBed = normalizeHour(currentBedtime + signedShift)
        let targetWake = normalizeHour(currentWake + signedShift)

        // Light window: based on PRC
        // For advance (east): light in the morning (after Tmin) advances the clock
        // For delay (west): light in the evening (before Tmin) delays the clock
        let lightWindow: TimeWindow
        let avoidLightWindow: TimeWindow

        if direction == .east {
            // Morning light after wake for ~90 min
            let lightStart = targetWake
            let lightEnd = normalizeHour(targetWake + 1.5)
            lightWindow = TimeWindow(start: lightStart, end: lightEnd)
            // Avoid light before Tmin (late night/early morning)
            let avoidStart = normalizeHour(targetBed - 2)
            avoidLightWindow = TimeWindow(start: avoidStart, end: targetWake)
        } else {
            // Evening light before bed for ~90 min
            let lightStart = normalizeHour(targetBed - 2)
            let lightEnd = normalizeHour(targetBed - 0.5)
            lightWindow = TimeWindow(start: lightStart, end: lightEnd)
            // Avoid morning light
            let avoidEnd = normalizeHour(targetWake + 2)
            avoidLightWindow = TimeWindow(start: targetWake, end: avoidEnd)
        }

        // Melatonin: 5h before target bedtime for advance,
        // at wake for delay (opposite to its PRC)
        let melatoninTime: Double
        if direction == .east {
            melatoninTime = normalizeHour(targetBed - 5)
        } else {
            melatoninTime = normalizeHour(targetWake + 0.5)
        }

        // Caffeine deadline: 8h before target bedtime
        let caffeineDeadline = normalizeHour(targetBed - 8)

        // Meal advice key based on direction
        let mealAdviceKey: String
        if direction == .east {
            mealAdviceKey = dayOffset < 0 ? "jetlag.meal.preAdvance" : "jetlag.meal.postAdvance"
        } else {
            mealAdviceKey = dayOffset < 0 ? "jetlag.meal.preDelay" : "jetlag.meal.postDelay"
        }

        return JetLagDay(
            dayOffset: dayOffset,
            lightWindow: lightWindow,
            avoidLightWindow: avoidLightWindow,
            melatoninTime: melatoninTime,
            mealAdviceKey: mealAdviceKey,
            caffeineDeadline: caffeineDeadline,
            targetBedtime: targetBed,
            targetWake: targetWake
        )
    }

    // MARK: - Helpers

    /// Normalize clock hour to 0–24 range.
    static func normalizeHour(_ h: Double) -> Double {
        var result = h.truncatingRemainder(dividingBy: 24)
        if result < 0 { result += 24 }
        return result
    }
}
