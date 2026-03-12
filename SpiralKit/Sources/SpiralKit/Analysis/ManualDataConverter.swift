import Foundation

/// Converts manually recorded sleep episodes into SleepRecord objects.
/// Port of src/utils/manualData.js from the Spiral Journey web project.
public enum ManualDataConverter {

    /// Convert sleep episodes into an array of SleepRecord objects (one per day).
    /// - Parameters:
    ///   - episodes: Array of SleepEpisode with start/end as absolute hours from day 0 00:00
    ///   - numDays: Number of days to generate records for
    ///   - startDate: Date for day 0 (defaults to today)
    /// - Returns: Array of SleepRecord, one per day, with cosinor analysis applied
    public static func convert(
        episodes: [SleepEpisode],
        numDays: Int,
        startDate: Date = Date()
    ) -> [SleepRecord] {
        let calendar = Calendar.current
        var records: [SleepRecord] = []

        for day in 0..<numDays {
            let dayStart = Double(day) * 24
            let dayDate  = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
            let dow      = calendar.component(.weekday, from: dayDate)
            let isWeekend = (dow == 1 || dow == 7)

            // Activity: sleeping = 0.05, awake = 0.95
            func isSleeping(at absH: Double) -> Bool {
                episodes.contains { ep in absH >= ep.start && absH < ep.end }
            }

            var hourlyActivity: [HourlyActivity] = []
            for h in 0..<24 {
                let sleeping = isSleeping(at: dayStart + Double(h))
                hourlyActivity.append(HourlyActivity(hour: h, activity: sleeping ? 0.05 : 0.95))
            }

            // Find main sleep episode overlapping this day
            var mainSleep: SleepEpisode? = nil
            var totalSleep = 0.0
            var mainOverlap = 0.0

            for ep in episodes {
                let overlapStart = max(ep.start, dayStart)
                let overlapEnd   = min(ep.end, dayStart + 24)
                let overlap = max(0, overlapEnd - overlapStart)
                if overlap > 0 {
                    totalSleep += overlap
                    if overlap > mainOverlap {
                        mainOverlap = overlap
                        mainSleep = ep
                    }
                }
            }

            let bedtime  = mainSleep.map { $0.start.truncatingRemainder(dividingBy: 24) } ?? 23.5
            let wakeup   = mainSleep.map { $0.end.truncatingRemainder(dividingBy: 24) }   ?? 7.0

            // Phase intervals at 15-min resolution.
            // If the covering episode carries a HealthKit phase, use it directly.
            // Manual episodes (phase == nil) fall back to .deep while sleeping.
            var phases: [PhaseInterval] = []
            var t = 0.0
            while t < 24 {
                let absT = dayStart + t
                let coveringEpisode = episodes.first { ep in absT >= ep.start && absT < ep.end }
                let phase: SleepPhase
                if let ep = coveringEpisode {
                    phase = ep.phase ?? .deep
                } else {
                    phase = .awake
                }
                phases.append(PhaseInterval(hour: t, phase: phase, timestamp: absT))
                t += 0.25
            }

            let cosinor = CosinorAnalysis.fit(hourlyActivity)

            records.append(SleepRecord(
                day:           day,
                date:          dayDate,
                isWeekend:     isWeekend,
                bedtimeHour:   bedtime,
                wakeupHour:    wakeup,
                sleepDuration: totalSleep,
                phases:        phases,
                hourlyActivity: hourlyActivity,
                cosinor:       cosinor,
                driftMinutes:  0
            ))
        }

        // Compute cumulative acrophase drift
        for i in 1..<records.count {
            var drift = records[i].cosinor.acrophase - records[i - 1].cosinor.acrophase
            if drift > 12  { drift -= 24 }
            if drift < -12 { drift += 24 }
            let prev = records[i - 1].driftMinutes
            records[i] = SleepRecord(
                id:            records[i].id,
                day:           records[i].day,
                date:          records[i].date,
                isWeekend:     records[i].isWeekend,
                bedtimeHour:   records[i].bedtimeHour,
                wakeupHour:    records[i].wakeupHour,
                sleepDuration: records[i].sleepDuration,
                phases:        records[i].phases,
                hourlyActivity: records[i].hourlyActivity,
                cosinor:       records[i].cosinor,
                driftMinutes:  prev + drift * 60
            )
        }

        return records
    }
}
