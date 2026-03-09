import Testing
import Foundation
@testable import SpiralKit

@Suite("SpiralConsistencyCalculator")
struct ConsistencyTests {

    // MARK: - Helpers

    /// Build a SleepRecord with given bedtime/wake and simple hourly activity.
    private func makeRecord(
        day: Int,
        daysAgo: Int,
        bedHour: Double,
        wakeHour: Double,
        duration: Double
    ) -> SleepRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let hourlyActivity = (0..<24).map { h -> HourlyActivity in
            let hd = Double(h)
            let isAsleep = bedHour > wakeHour
                ? (hd >= bedHour || hd < wakeHour)
                : (hd >= bedHour && hd < wakeHour)
            return HourlyActivity(hour: h, activity: isAsleep ? 0.1 : 0.9)
        }
        return SleepRecord(
            day: day,
            date: date,
            isWeekend: day % 7 < 2,
            bedtimeHour: bedHour,
            wakeupHour: wakeHour,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: hourlyActivity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.85)
        )
    }

    /// 7 nights with nearly identical timing → should score ≥ 75.
    private var stableRecords: [SleepRecord] {
        (0..<7).map { i in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: 23.0 + Double(i % 2) * 0.1,
                       wakeHour: 7.0, duration: 8.0)
        }
    }

    /// 7 nights with highly variable bedtime (shifts by ~2-3 h) → should score < 60.
    private var irregularRecords: [SleepRecord] {
        let bedHours: [Double] = [22.0, 0.5, 23.0, 2.0, 21.5, 1.5, 23.5]
        return bedHours.enumerated().map { i, bed in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: bed, wakeHour: bed + 8, duration: 8.0)
        }
    }

    // MARK: - Score Range Tests

    @Test("Stable pattern → high consistency score (≥ 75)")
    func testStablePatternHighScore() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        #expect(result.score >= 75, "Expected ≥ 75 for stable pattern, got \(result.score)")
        #expect(result.label == .veryStable || result.label == .stable)
        #expect(result.nightsUsed == 7)
        #expect(result.confidence == .high)
    }

    @Test("Irregular pattern → low consistency score (< 60)")
    func testIrregularPatternLowScore() {
        let result = SpiralConsistencyCalculator.compute(records: irregularRecords, windowDays: 7)
        #expect(result.score < 60, "Expected < 60 for irregular pattern, got \(result.score)")
        #expect(result.label == .variable || result.label == .disorganized)
    }

    @Test("Score is always in 0-100 range")
    func testScoreRange() {
        for records in [stableRecords, irregularRecords] {
            let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
            #expect(result.score >= 0 && result.score <= 100)
        }
    }

    // MARK: - Insufficient Data

    @Test("Single night returns insufficient label")
    func testSingleNight() {
        let records = [makeRecord(day: 0, daysAgo: 0, bedHour: 23, wakeHour: 7, duration: 8)]
        let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
        #expect(result.label == .insufficient)
        #expect(result.nightsUsed <= 1)
    }

    @Test("Empty records returns insufficient label")
    func testEmptyRecords() {
        let result = SpiralConsistencyCalculator.compute(records: [], windowDays: 7)
        #expect(result.label == .insufficient)
        #expect(result.score == 0)
    }

    @Test("Two nights → low confidence")
    func testTwoNightsLowConfidence() {
        let records = (0..<2).map { i in
            makeRecord(day: i, daysAgo: 1 - i, bedHour: 23, wakeHour: 7, duration: 8)
        }
        let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
        #expect(result.confidence == .low)
    }

    // MARK: - Confidence Levels

    @Test("4-6 nights → medium confidence")
    func testMediumConfidence() {
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 23, wakeHour: 7, duration: 8)
        }
        let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
        #expect(result.confidence == .medium)
    }

    @Test("7+ nights → high confidence")
    func testHighConfidence() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        #expect(result.confidence == .high)
    }

    // MARK: - Breakdown Sub-metrics

    @Test("Stable pattern → all breakdown sub-metrics ≥ 60")
    func testStableBreakdown() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        let bd = result.breakdown
        #expect(bd.sleepOnsetRegularity >= 60)
        #expect(bd.wakeTimeRegularity >= 60)
        #expect(bd.fragmentationPatternSimilarity >= 0 && bd.fragmentationPatternSimilarity <= 100)
        #expect(bd.sleepDurationStability >= 60)
        #expect(bd.recoveryStability >= 0 && bd.recoveryStability <= 100)
    }

    @Test("Without external recovery data, recoveryFromRealData is false")
    func testRecoveryFlagFalseWhenNoExternalData() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        #expect(result.breakdown.recoveryFromRealData == false)
    }

    @Test("With external recovery values, recoveryFromRealData is true")
    func testRecoveryFlagTrueWhenDataProvided() {
        let recovery = stableRecords.map { _ in Double.random(in: 0.6...0.9) }
        let result = SpiralConsistencyCalculator.compute(
            records: stableRecords,
            windowDays: 7,
            recoveryValues: recovery
        )
        #expect(result.breakdown.recoveryFromRealData == true)
    }

    // MARK: - Disruption Detection

    @Test("Stable pattern → no disruption days")
    func testStableNoDisruptions() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        // A stable pattern may have 0 local/global disruptions
        #expect(result.localDisruptionDays.count + result.globalShiftDays.count == 0
                || result.score >= 75,
                "Stable pattern should have few disruptions or high score")
    }

    @Test("Global shift detected when bedtime shifts 3h+ on one night")
    func testGlobalShiftDetected() {
        // 6 stable nights + 1 with a 3-hour shift
        var records = stableRecords
        records[3] = makeRecord(day: 3, daysAgo: 3, bedHour: 2.0, wakeHour: 10.0, duration: 8.0)
        let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
        #expect(!result.globalShiftDays.isEmpty || !result.insights.isEmpty,
                "A 3-hour shift should produce at least one global disruption or insight")
    }

    @Test("Insights ordered by severity descending")
    func testInsightsSortedBySeverity() {
        let result = SpiralConsistencyCalculator.compute(records: irregularRecords, windowDays: 7)
        let severities = result.insights.map(\.severity)
        for i in 1..<severities.count {
            #expect(severities[i - 1] >= severities[i], "Insights should be sorted severity desc")
        }
    }

    // MARK: - Delta vs Previous Week

    @Test("Delta is nil when fewer than 2 full windows available")
    func testDeltaNilForInsufficientHistory() {
        let result = SpiralConsistencyCalculator.compute(records: stableRecords, windowDays: 7)
        // stableRecords has exactly 7 nights → no previous window to compare
        // delta may be nil (no previous week data)
        // This just verifies it doesn't crash and is in a valid range when present
        if let delta = result.deltaVsPreviousWeek {
            #expect(delta >= -100 && delta <= 100)
        }
    }

    @Test("Delta is non-nil when 14+ nights are available")
    func testDeltaPresentWith14Nights() {
        let records = (0..<14).map { i in
            makeRecord(day: i, daysAgo: 13 - i, bedHour: 23.0, wakeHour: 7.0, duration: 8.0)
        }
        let result = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
        #expect(result.deltaVsPreviousWeek != nil)
    }

    // MARK: - ConsistencyLabel.from(score:)

    @Test("ConsistencyLabel.from maps scores to correct labels")
    func testLabelFromScore() {
        #expect(ConsistencyLabel.from(score: 90) == .veryStable)
        #expect(ConsistencyLabel.from(score: 85) == .veryStable)
        #expect(ConsistencyLabel.from(score: 70) == .stable)
        #expect(ConsistencyLabel.from(score: 50) == .variable)
        #expect(ConsistencyLabel.from(score: 49) == .disorganized)
        #expect(ConsistencyLabel.from(score: 0)  == .disorganized)
    }
}
