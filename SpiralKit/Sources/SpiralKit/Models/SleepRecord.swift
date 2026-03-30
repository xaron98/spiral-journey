import Foundation

/// A single day's sleep record — the core data structure for all analysis.
/// Mirrors the day objects produced by the web project's convertEpisodesToSleepData().
public struct SleepRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var day: Int               // 0-based day index
    public var date: Date
    public var isWeekend: Bool
    public var bedtimeHour: Double    // clock hour 0-24 when sleep started
    public var wakeupHour: Double     // clock hour 0-24 when sleep ended
    public var sleepDuration: Double  // total sleep hours
    public var phases: [PhaseInterval]
    public var hourlyActivity: [HourlyActivity]  // 24 entries, one per clock hour
    public var cosinor: CosinorResult
    public var driftMinutes: Double   // cumulative acrophase drift in minutes

    public init(
        id: UUID = UUID(),
        day: Int,
        date: Date,
        isWeekend: Bool,
        bedtimeHour: Double,
        wakeupHour: Double,
        sleepDuration: Double,
        phases: [PhaseInterval],
        hourlyActivity: [HourlyActivity],
        cosinor: CosinorResult,
        driftMinutes: Double = 0
    ) {
        self.id = id
        self.day = day
        self.date = date
        self.isWeekend = isWeekend
        self.bedtimeHour = bedtimeHour
        self.wakeupHour = wakeupHour
        self.sleepDuration = sleepDuration
        self.phases = phases
        self.hourlyActivity = hourlyActivity
        self.cosinor = cosinor
        self.driftMinutes = driftMinutes
    }

    // MARK: - Custom Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case id, day, date, isWeekend, bedtimeHour, wakeupHour
        case sleepDuration, phases, hourlyActivity, cosinor, driftMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        day = try c.decode(Int.self, forKey: .day)
        date = try c.decode(Date.self, forKey: .date)
        isWeekend = try c.decode(Bool.self, forKey: .isWeekend)
        bedtimeHour = try c.decode(Double.self, forKey: .bedtimeHour)
        wakeupHour = try c.decode(Double.self, forKey: .wakeupHour)
        sleepDuration = try c.decode(Double.self, forKey: .sleepDuration)
        phases = try c.decode([PhaseInterval].self, forKey: .phases)
        hourlyActivity = try c.decode([HourlyActivity].self, forKey: .hourlyActivity)
        cosinor = try c.decode(CosinorResult.self, forKey: .cosinor)
        driftMinutes = try c.decodeIfPresent(Double.self, forKey: .driftMinutes) ?? 0
    }
}
