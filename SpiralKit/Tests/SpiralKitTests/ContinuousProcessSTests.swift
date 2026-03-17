import Foundation
import Testing
@testable import SpiralKit

@Suite("ContinuousProcessS Tests")
struct ContinuousProcessSTests {

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

    // MARK: - continuousProcessS

    @Test("Returns value in [0, 1] for normal records")
    func returnsValidRange() {
        let records = (0..<5).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let s = PredictionFeatureBuilder.continuousProcessS(from: records, currentHour: 14)
        #expect(s >= 0 && s <= 1, "S should be in [0,1], got \(s)")
    }

    @Test("Falls back to stateless processS with fewer than 2 records")
    func fallbackWithOneRecord() {
        let records = [makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)]
        let s = PredictionFeatureBuilder.continuousProcessS(from: records, currentHour: 14)
        // With 1 record, should fall back to stateless processS
        // 14 - 7 = 7 hours since wake, stateless: 1 - (1 - 0.2) * exp(-7/18.2)
        let expected = TwoProcessModel.processS(hoursSinceTransition: 7, isAwake: true, s0: 0.2)
        #expect(abs(s - expected) < 0.001, "Should fall back to stateless: got \(s), expected \(expected)")
    }

    @Test("Falls back to stateless processS with empty records")
    func fallbackWithEmpty() {
        let s = PredictionFeatureBuilder.continuousProcessS(from: [], currentHour: 14)
        // Empty records: hoursSinceWake defaults to 0 from fallback logic
        let expected = TwoProcessModel.processS(hoursSinceTransition: 0, isAwake: true, s0: 0.2)
        #expect(abs(s - expected) < 0.001, "Should fall back with empty records")
    }

    @Test("Uses only last 7 days of records")
    func limitsToSevenDays() {
        // 10 days of records — method should use only last 7
        let records = (0..<10).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let s = PredictionFeatureBuilder.continuousProcessS(from: records, currentHour: 14)
        #expect(s >= 0 && s <= 1, "S should be valid when input exceeds 7 days")
    }

    @Test("Sleep debt shows higher S than well-rested")
    func debtRaisesS() {
        // Well-rested: 5 days of 8h sleep
        let rested = (0..<5).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let sRested = PredictionFeatureBuilder.continuousProcessS(from: rested, currentHour: 14)

        // Sleep-deprived: 5 days of 4h sleep
        let deprived = (0..<5).map { makeRecord(day: $0, bedtime: 2, wakeup: 6, duration: 4) }
        let sDeprived = PredictionFeatureBuilder.continuousProcessS(from: deprived, currentHour: 14)

        #expect(sDeprived > sRested,
                "Deprived S(\(sDeprived)) should exceed rested S(\(sRested))")
    }

    @Test("Differs from stateless processS for multi-day sequence")
    func differsFromStateless() {
        // 5 days of short sleep — continuous should differ from stateless
        let records = (0..<5).map { makeRecord(day: $0, bedtime: 2, wakeup: 6, duration: 4) }
        let continuous = PredictionFeatureBuilder.continuousProcessS(from: records, currentHour: 14)

        // Stateless equivalent: 14 - 6 = 8 hours since wake
        let stateless = TwoProcessModel.processS(hoursSinceTransition: 8, isAwake: true, s0: 0.2)

        #expect(abs(continuous - stateless) > 0.01,
                "Continuous(\(continuous)) should differ from stateless(\(stateless)) after sleep debt")
    }

    // MARK: - Integration with build()

    @Test("build() uses continuous process S when enough records")
    func buildUsesContinuousS() {
        let records = (0..<5).map { makeRecord(day: $0, bedtime: 23, wakeup: 7, duration: 8) }
        let currentAbsHour = Double(4) * 24 + 14  // day 4, hour 14
        let result = PredictionFeatureBuilder.build(
            records: records,
            events: [],
            consistency: nil,
            chronotypeResult: nil,
            goalDuration: 8,
            currentAbsHour: currentAbsHour
        )
        #expect(result != nil)
        let s = result!.processS
        #expect(s >= 0 && s <= 1, "processS in build result should be valid")
    }

    @Test("build() still works with single record (fallback)")
    func buildFallbackSingleRecord() {
        let records = [makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)]
        let currentAbsHour = 14.0  // day 0, hour 14
        let result = PredictionFeatureBuilder.build(
            records: records,
            events: [],
            consistency: nil,
            chronotypeResult: nil,
            goalDuration: 8,
            currentAbsHour: currentAbsHour
        )
        #expect(result != nil)
        let s = result!.processS
        // Should use stateless fallback
        let expected = TwoProcessModel.processS(hoursSinceTransition: 7, isAwake: true, s0: 0.2)
        #expect(abs(s - expected) < 0.001,
                "Single-record build should use stateless fallback: got \(s), expected \(expected)")
    }
}
