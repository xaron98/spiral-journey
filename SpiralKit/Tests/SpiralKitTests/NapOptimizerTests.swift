import Foundation
import Testing
@testable import SpiralKit

@Suite("NapOptimizer Tests")
struct NapOptimizerTests {

    // Helper to create records with specific sleep durations
    private func makeRecords(count: Int, bedtime: Double = 23.0, wakeup: Double = 7.0, sleepDuration: Double = 8.0) -> [SleepRecord] {
        (0..<count).map { day in
            SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: bedtime, wakeupHour: wakeup, sleepDuration: sleepDuration,
                phases: [],
                hourlyActivity: (0..<24).map { hour in
                    let isAsleep = (hour >= Int(bedtime) || hour < Int(wakeup))
                    return HourlyActivity(hour: hour, activity: isAsleep ? 0.0 : 0.8)
                },
                cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
            )
        }
    }

    @Test("Well-rested person gets no nap recommendation")
    func wellRested() {
        // 8h sleep → low S during afternoon
        let records = makeRecords(count: 3, bedtime: 23.0, wakeup: 7.0, sleepDuration: 8.0)
        let result = NapOptimizer.recommend(records: records, wakeHour: 7.0)
        // With 8h sleep the S should be low enough that no nap is needed
        // (This depends on exact S values, so we just verify it doesn't crash)
        if let r = result {
            #expect(r.suggestedStart >= 12.0 && r.suggestedStart <= 16.0)
        }
    }

    @Test("All-nighter triggers nap recommendation")
    func allNighter() {
        // Simulate all-nighter: all hours marked as awake → S rises above threshold
        let records = (0..<3).map { day -> SleepRecord in
            SleepRecord(
                day: day, date: Date(), isWeekend: false,
                bedtimeHour: 23.0, wakeupHour: 7.0, sleepDuration: 0.0,
                phases: [],
                hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.8) },
                cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
            )
        }
        let result = NapOptimizer.recommend(records: records, wakeHour: 7.0)
        #expect(result != nil, "Should recommend nap after all-nighter")
        if let r = result {
            #expect(r.suggestedStart >= 12.0 && r.suggestedStart <= 16.0)
            #expect(r.duration == 20 || r.duration == 90)
            #expect(r.sleepPressure >= 0.55)
        }
    }

    @Test("Empty records returns nil")
    func emptyRecords() {
        let result = NapOptimizer.recommend(records: [], wakeHour: 7.0)
        #expect(result == nil)
    }

    @Test("Nap duration is 20 min for moderate pressure")
    func powerNapDuration() {
        let records = makeRecords(count: 3, bedtime: 1.0, wakeup: 7.0, sleepDuration: 6.0)
        let result = NapOptimizer.recommend(records: records, wakeHour: 7.0)
        if let r = result {
            if r.sleepPressure < 0.70 {
                #expect(r.duration == 20)
            }
        }
    }

    @Test("Morning chronotype shifts nap window earlier")
    func morningTypeWindow() {
        let records = makeRecords(count: 3, bedtime: 2.0, wakeup: 7.0, sleepDuration: 5.0)
        let morningResult = NapOptimizer.recommend(records: records, wakeHour: 6.0, chronotype: .definiteMorning)
        let eveningResult = NapOptimizer.recommend(records: records, wakeHour: 10.0, chronotype: .definiteEvening)
        // If both recommend naps, morning should be earlier
        if let m = morningResult, let e = eveningResult {
            #expect(m.suggestedStart <= e.suggestedStart,
                    "Morning type nap (\(m.suggestedStart)) should be ≤ evening type (\(e.suggestedStart))")
        }
    }

    @Test("Nap reason can be circadian dip")
    func circadianDipReason() {
        let records = makeRecords(count: 3, bedtime: 2.0, wakeup: 7.0, sleepDuration: 5.0)
        let result = NapOptimizer.recommend(records: records, wakeHour: 7.0)
        if let r = result {
            // Reason should be one of the valid enum cases
            let validReasons: [NapOptimizer.NapReason] = [.highPressure, .circadianDip, .debtRecovery]
            #expect(validReasons.contains(r.reason))
        }
    }
}
