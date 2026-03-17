import Testing
import Foundation
@testable import SpiralKit

@Suite("DayNucleotide")
struct DayNucleotideTests {

    // MARK: - Helpers

    private func makeRecord(
        day: Int,
        bedtime: Double,
        wakeup: Double,
        duration: Double,
        cosinor: CosinorResult = .empty,
        driftMinutes: Double = 0
    ) -> SleepRecord {
        SleepRecord(
            day: day,
            date: Date(),
            isWeekend: day % 7 >= 5,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: (0..<24).map { h in
                let asleep = bedtime > wakeup
                    ? (Double(h) >= bedtime || Double(h) < wakeup)
                    : (Double(h) >= bedtime && Double(h) < wakeup)
                return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
            },
            cosinor: cosinor,
            driftMinutes: driftMinutes
        )
    }

    private func makeEvent(type: EventType, day: Int, hourInDay: Double, period: Double = 24) -> CircadianEvent {
        CircadianEvent(
            type: type,
            absoluteHour: Double(day) * period + hourInDay
        )
    }

    // MARK: - Feature Count

    @Test("Feature vector has exactly 16 elements")
    func testFeatureCount() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(nuc.features.count == 16)
        #expect(nuc.features.count == DayNucleotide.featureCount)
    }

    // MARK: - Circular Encoding

    @Test("Bedtime circular encoding produces valid sin/cos pair")
    func testBedtimeCircular() {
        let record = makeRecord(day: 0, bedtime: 6, wakeup: 14, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])

        let sinVal = nuc[.bedtimeSin]
        let cosVal = nuc[.bedtimeCos]
        // sin^2 + cos^2 should equal 1
        let magnitude = sinVal * sinVal + cosVal * cosVal
        #expect(abs(magnitude - 1.0) < 1e-10, "sin^2 + cos^2 should be 1, got \(magnitude)")
    }

    @Test("Wakeup circular encoding produces valid sin/cos pair")
    func testWakeupCircular() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])

        let sinVal = nuc[.wakeupSin]
        let cosVal = nuc[.wakeupCos]
        let magnitude = sinVal * sinVal + cosVal * cosVal
        #expect(abs(magnitude - 1.0) < 1e-10)
    }

    @Test("Midnight bedtime encodes correctly (hour = 0)")
    func testMidnightBedtime() {
        let record = makeRecord(day: 0, bedtime: 0, wakeup: 8, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])

        // sin(0) = 0, cos(0) = 1
        #expect(abs(nuc[.bedtimeSin]) < 1e-10)
        #expect(abs(nuc[.bedtimeCos] - 1.0) < 1e-10)
    }

    // MARK: - Sleep Duration

    @Test("Sleep duration normalized to [0, 1] via /12")
    func testSleepDurationNormalization() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(abs(nuc[.sleepDuration] - 8.0 / 12.0) < 1e-10)
    }

    @Test("Sleep duration capped at 1.0 for 12+ hours")
    func testSleepDurationCap() {
        let record = makeRecord(day: 0, bedtime: 20, wakeup: 10, duration: 14)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(nuc[.sleepDuration] == 1.0)
    }

    // MARK: - Process S

    @Test("Process S passed through correctly")
    func testProcessS() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [], processS: 0.73)
        #expect(abs(nuc[.processS] - 0.73) < 1e-10)
    }

    @Test("Process S clamped to [0, 1]")
    func testProcessSClamped() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let over = DayNucleotide.encode(record: record, events: [], processS: 1.5)
        #expect(over[.processS] == 1.0)
        let under = DayNucleotide.encode(record: record, events: [], processS: -0.3)
        #expect(under[.processS] == 0.0)
    }

    // MARK: - Cosinor Features

    @Test("Cosinor acrophase normalized to [0, 1] via /24")
    func testCosinorAcrophase() {
        let cosinor = CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.85)
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, cosinor: cosinor)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(abs(nuc[.cosinorAcrophase] - 15.0 / 24.0) < 1e-10)
    }

    @Test("Cosinor R-squared passed through")
    func testCosinorR2() {
        let cosinor = CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.85)
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, cosinor: cosinor)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(abs(nuc[.cosinorR2] - 0.85) < 1e-10)
    }

    // MARK: - Context Events

    @Test("Caffeine count normalized by /5 with cap at 1.0")
    func testCaffeineEncoding() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let events = (0..<3).map { i in makeEvent(type: .caffeine, day: 0, hourInDay: 8 + Double(i)) }
        let nuc = DayNucleotide.encode(record: record, events: events)
        #expect(abs(nuc[.caffeine] - 3.0 / 5.0) < 1e-10)

        // Test cap: 7 coffees should still be 1.0
        let manyEvents = (0..<7).map { i in makeEvent(type: .caffeine, day: 0, hourInDay: Double(i)) }
        let capped = DayNucleotide.encode(record: record, events: manyEvents)
        #expect(capped[.caffeine] == 1.0)
    }

    @Test("Exercise is binary (0 or 1)")
    func testExerciseBinary() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let noExercise = DayNucleotide.encode(record: record, events: [])
        #expect(noExercise[.exercise] == 0.0)

        let events = [makeEvent(type: .exercise, day: 0, hourInDay: 10)]
        let withExercise = DayNucleotide.encode(record: record, events: events)
        #expect(withExercise[.exercise] == 1.0)

        // Multiple exercise events still produce 1.0
        let multiEvents = [
            makeEvent(type: .exercise, day: 0, hourInDay: 8),
            makeEvent(type: .exercise, day: 0, hourInDay: 17),
        ]
        let multiExercise = DayNucleotide.encode(record: record, events: multiEvents)
        #expect(multiExercise[.exercise] == 1.0)
    }

    @Test("Alcohol count normalized by /3 with cap at 1.0")
    func testAlcoholEncoding() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let events = [
            makeEvent(type: .alcohol, day: 0, hourInDay: 19),
            makeEvent(type: .alcohol, day: 0, hourInDay: 20),
        ]
        let nuc = DayNucleotide.encode(record: record, events: events)
        #expect(abs(nuc[.alcohol] - 2.0 / 3.0) < 1e-10)
    }

    @Test("Melatonin is binary (0 or 1)")
    func testMelatoninBinary() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let noMel = DayNucleotide.encode(record: record, events: [])
        #expect(noMel[.melatonin] == 0.0)

        let events = [makeEvent(type: .melatonin, day: 0, hourInDay: 22)]
        let withMel = DayNucleotide.encode(record: record, events: events)
        #expect(withMel[.melatonin] == 1.0)
    }

    @Test("Stress count normalized by /3 with cap at 1.0")
    func testStressEncoding() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let events = (0..<5).map { _ in makeEvent(type: .stress, day: 0, hourInDay: 14) }
        let nuc = DayNucleotide.encode(record: record, events: events)
        #expect(nuc[.stress] == 1.0) // 5/3 capped at 1.0
    }

    // MARK: - Event Day Filtering

    @Test("Events from other days are excluded")
    func testEventDayFiltering() {
        let record = makeRecord(day: 1, bedtime: 23, wakeup: 7, duration: 8)
        let events = [
            makeEvent(type: .caffeine, day: 0, hourInDay: 10), // day 0 — excluded
            makeEvent(type: .caffeine, day: 1, hourInDay: 10), // day 1 — included
            makeEvent(type: .caffeine, day: 2, hourInDay: 10), // day 2 — excluded
        ]
        let nuc = DayNucleotide.encode(record: record, events: events)
        #expect(abs(nuc[.caffeine] - 1.0 / 5.0) < 1e-10, "Only one caffeine event should be counted for day 1")
    }

    // MARK: - Weekend

    @Test("Weekend flag encoded correctly")
    func testWeekendEncoding() {
        // day 5 → isWeekend = true (5 % 7 >= 5)
        let weekendRecord = makeRecord(day: 5, bedtime: 23, wakeup: 7, duration: 8)
        let weekendNuc = DayNucleotide.encode(record: weekendRecord, events: [])
        #expect(weekendNuc[.isWeekend] == 1.0)

        // day 3 → isWeekend = false
        let weekdayRecord = makeRecord(day: 3, bedtime: 23, wakeup: 7, duration: 8)
        let weekdayNuc = DayNucleotide.encode(record: weekdayRecord, events: [])
        #expect(weekdayNuc[.isWeekend] == 0.0)
    }

    // MARK: - Drift Minutes

    @Test("Drift minutes normalized by /120 and clamped to [-1, 1]")
    func testDriftMinutes() {
        let record60 = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, driftMinutes: 60)
        let nuc60 = DayNucleotide.encode(record: record60, events: [])
        #expect(abs(nuc60[.driftMinutes] - 0.5) < 1e-10)

        // Large positive drift clamped to 1.0
        let recordBig = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, driftMinutes: 200)
        let nucBig = DayNucleotide.encode(record: recordBig, events: [])
        #expect(nucBig[.driftMinutes] == 1.0)

        // Negative drift
        let recordNeg = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, driftMinutes: -60)
        let nucNeg = DayNucleotide.encode(record: recordNeg, events: [])
        #expect(abs(nucNeg[.driftMinutes] - (-0.5)) < 1e-10)

        // Large negative drift clamped to -1.0
        let recordNegBig = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8, driftMinutes: -200)
        let nucNegBig = DayNucleotide.encode(record: recordNegBig, events: [])
        #expect(nucNegBig[.driftMinutes] == -1.0)
    }

    // MARK: - Sleep Quality

    @Test("Sleep quality = min(duration/goal, 1) * cosinorR2")
    func testSleepQuality() {
        let cosinor = CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.8)
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 7, cosinor: cosinor)
        let nuc = DayNucleotide.encode(record: record, events: [], goalDuration: 8)

        let expected = (7.0 / 8.0) * 0.8
        #expect(abs(nuc[.sleepQuality] - expected) < 1e-10)
    }

    @Test("Sleep quality capped when duration exceeds goal")
    func testSleepQualityCapped() {
        let cosinor = CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.9)
        let record = makeRecord(day: 0, bedtime: 22, wakeup: 8, duration: 10, cosinor: cosinor)
        let nuc = DayNucleotide.encode(record: record, events: [], goalDuration: 8)

        // min(10/8, 1) = 1.0 → quality = 1.0 * 0.9 = 0.9
        #expect(abs(nuc[.sleepQuality] - 0.9) < 1e-10)
    }

    // MARK: - Day Index

    @Test("Nucleotide preserves day index from record")
    func testDayIndex() {
        let record = makeRecord(day: 42, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide.encode(record: record, events: [])
        #expect(nuc.day == 42)
    }
}
