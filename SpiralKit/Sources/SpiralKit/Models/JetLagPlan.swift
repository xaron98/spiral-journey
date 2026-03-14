import Foundation

// MARK: - Jet Lag Plan

/// A multi-day adaptation plan for crossing timezones.
///
/// Generated from the user's current schedule + PRCs to optimize
/// light/melatonin/meal timing for phase shifting.
public struct JetLagPlan: Codable, Sendable, Equatable {
    /// Timezone offset in hours (-12 to +12).
    public var timezoneOffsetHours: Int
    /// Planned travel date.
    public var travelDate: Date
    /// Direction of shift.
    public var direction: Direction
    /// Day-by-day plan (pre-travel + post-travel).
    public var days: [JetLagDay]
    /// Estimated days to full adaptation.
    public var estimatedAdaptationDays: Int

    public init(
        timezoneOffsetHours: Int,
        travelDate: Date,
        direction: Direction,
        days: [JetLagDay],
        estimatedAdaptationDays: Int
    ) {
        self.timezoneOffsetHours = timezoneOffsetHours
        self.travelDate = travelDate
        self.direction = direction
        self.days = days
        self.estimatedAdaptationDays = estimatedAdaptationDays
    }
}

// MARK: - Direction

public extension JetLagPlan {
    /// Direction of circadian shift required.
    enum Direction: String, Codable, Sendable {
        case east   // Phase advance (sleep earlier)
        case west   // Phase delay (sleep later)
    }
}

// MARK: - Jet Lag Day

/// One day of the jet lag adaptation plan.
public struct JetLagDay: Codable, Sendable, Identifiable, Equatable {
    public var id: Int { dayOffset }

    /// Day offset from travel: -3, -2, -1, 0 (travel), 1, 2, ...
    public var dayOffset: Int
    /// Window for bright light exposure.
    public var lightWindow: TimeWindow?
    /// Window to avoid bright light.
    public var avoidLightWindow: TimeWindow?
    /// Recommended melatonin intake time (clock hour).
    public var melatoninTime: Double?
    /// Meal timing advice localization key.
    public var mealAdviceKey: String?
    /// Caffeine deadline (no caffeine after this hour).
    public var caffeineDeadline: Double?
    /// Target bedtime for this day (clock hour).
    public var targetBedtime: Double?
    /// Target wake time for this day (clock hour).
    public var targetWake: Double?

    public init(
        dayOffset: Int,
        lightWindow: TimeWindow? = nil,
        avoidLightWindow: TimeWindow? = nil,
        melatoninTime: Double? = nil,
        mealAdviceKey: String? = nil,
        caffeineDeadline: Double? = nil,
        targetBedtime: Double? = nil,
        targetWake: Double? = nil
    ) {
        self.dayOffset = dayOffset
        self.lightWindow = lightWindow
        self.avoidLightWindow = avoidLightWindow
        self.melatoninTime = melatoninTime
        self.mealAdviceKey = mealAdviceKey
        self.caffeineDeadline = caffeineDeadline
        self.targetBedtime = targetBedtime
        self.targetWake = targetWake
    }
}

// MARK: - Time Window

/// A time window with start and end clock hours.
public struct TimeWindow: Codable, Sendable, Equatable {
    public var start: Double  // clock hour (0-24)
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}
