import Foundation
import Testing
@testable import SpiralKit

@Suite("TwoProcessModel Tests")
struct TwoProcessTests {

    // MARK: - Helpers

    private func makeRecord(day: Int, bedtime: Double, wakeup: Double, duration: Double) -> SleepRecord {
        SleepRecord(
            day: day,
            date: Date(),
            isWeekend: false,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: (0..<24).map { h in
                let asleep = (bedtime > wakeup)
                    ? (Double(h) >= bedtime || Double(h) < wakeup)
                    : (Double(h) >= bedtime && Double(h) < wakeup)
                return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
            },
            cosinor: .empty
        )
    }

    // MARK: - Legacy method regression

    @Test("Legacy compute returns 24 points per day")
    func legacyShape() {
        let records = [makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)]
        let result = TwoProcessModel.compute(records)
        #expect(result.count == 24)
    }

    @Test("Legacy S values are in [0, 1]")
    func legacySRange() {
        let records = (0..<3).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let result = TwoProcessModel.compute(records)
        for p in result {
            #expect(p.s >= 0 && p.s <= 1, "S out of range: \(p.s)")
        }
    }

    // MARK: - Continuous Process S

    @Test("Continuous compute returns 24 points per day")
    func continuousShape() {
        let records = (0..<5).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let result = TwoProcessModel.computeContinuous(records)
        #expect(result.count == 5 * 24)
    }

    @Test("Continuous S values are in [0, 1]")
    func continuousSRange() {
        let records = (0..<7).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let result = TwoProcessModel.computeContinuous(records)
        for p in result {
            #expect(p.s >= 0 && p.s <= 1, "S out of range: \(p.s) at day=\(p.day) hour=\(p.hour)")
        }
    }

    @Test("Sleep debt accumulates: short sleep raises next-day S baseline")
    func continuousDebtAccumulation() {
        // 4 days of only 4h sleep (bed 2:00, wake 6:00)
        let shortSleep = (0..<4).map { makeRecord(day: $0, bedtime: 2, wakeup: 6, duration: 4) }
        let result = TwoProcessModel.computeContinuous(shortSleep)

        // Compare S at wakeup hour (h=6) on day 0 vs day 3
        let sDay0Wake = result.first { $0.day == 0 && $0.hour == 6 }!.s
        let sDay3Wake = result.first { $0.day == 3 && $0.hour == 6 }!.s
        #expect(sDay3Wake > sDay0Wake,
                "Sleep debt should accumulate: day3 S(\(sDay3Wake)) should be > day0 S(\(sDay0Wake))")
    }

    @Test("Recovery: long sleep after deprivation lowers S")
    func continuousRecovery() {
        // 3 days of 4h sleep, then 1 day of 10h sleep
        var records = (0..<3).map { makeRecord(day: $0, bedtime: 2, wakeup: 6, duration: 4) }
        records.append(makeRecord(day: 3, bedtime: 22, wakeup: 8, duration: 10))

        let result = TwoProcessModel.computeContinuous(records)

        // S at end of day 3 (after 10h sleep) should be lower than end of day 2
        let sEndDay2 = result.last { $0.day == 2 }!.s
        let sEndDay3 = result.last { $0.day == 3 }!.s
        #expect(sEndDay3 < sEndDay2,
                "Recovery sleep should lower S: day3 end(\(sEndDay3)) < day2 end(\(sEndDay2))")
    }

    @Test("Continuous differs from legacy for multi-day sequences")
    func continuousDiffersFromLegacy() {
        // 3 days of short sleep — continuous should show different S values than legacy
        let records = (0..<3).map { makeRecord(day: $0, bedtime: 2, wakeup: 6, duration: 4) }
        let legacy = TwoProcessModel.compute(records)
        let continuous = TwoProcessModel.computeContinuous(records)

        // On day 2, continuous should differ because it carries debt forward
        let legacyDay2 = legacy.filter { $0.day == 2 }.map(\.s)
        let contDay2 = continuous.filter { $0.day == 2 }.map(\.s)

        var anyDifferent = false
        for i in 0..<min(legacyDay2.count, contDay2.count) {
            if abs(legacyDay2[i] - contDay2[i]) > 0.01 {
                anyDifferent = true
                break
            }
        }
        #expect(anyDifferent, "Continuous should differ from legacy on day 2 due to debt propagation")
    }

    @Test("Empty records returns empty result")
    func continuousEmpty() {
        let result = TwoProcessModel.computeContinuous([])
        #expect(result.isEmpty)
    }
}
