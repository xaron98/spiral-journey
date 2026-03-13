import Testing
import Foundation
@testable import SpiralKit

@Suite("CoachEngine")
struct CoachEngineTests {

    // MARK: - Fixtures

    /// Build a SleepRecord with given bedtime/wake and derived hourly activity.
    private func makeRecord(
        day: Int,
        daysAgo: Int = 0,
        bedHour: Double,
        wakeHour: Double,
        duration: Double,
        isWeekend: Bool = false
    ) -> SleepRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let hourlyActivity = (0..<24).map { h -> HourlyActivity in
            let hd = Double(h)
            let isAsleep = bedHour > wakeHour
                ? (hd >= bedHour || hd < wakeHour)
                : (hd >= bedHour && hd < wakeHour)
            return HourlyActivity(hour: h, activity: isAsleep ? 0.1 : 0.9)
        }
        // Acrophase: activity peaks in the middle of the awake window
        // Approximate: (wakeHour + (bedHour + 24 - wakeHour) / 2) if bed > wake
        let acrophase: Double
        if bedHour > wakeHour {
            let awakeCenter = wakeHour + (bedHour - wakeHour) / 2
            acrophase = awakeCenter
        } else {
            acrophase = (bedHour + wakeHour) / 2
        }
        return SleepRecord(
            day: day,
            date: date,
            isWeekend: isWeekend,
            bedtimeHour: bedHour,
            wakeupHour: wakeHour,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: hourlyActivity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: acrophase, period: 24, r2: 0.85)
        )
    }

    /// Produce SleepStats from an array of records (simplified, for test use).
    private func makeStats(from records: [SleepRecord]) -> SleepStats {
        guard !records.isEmpty else { return SleepStats() }
        let meanDur = records.map(\.sleepDuration).reduce(0, +) / Double(records.count)
        let meanAcro = records.map(\.cosinor.acrophase).reduce(0, +) / Double(records.count)
        let weekdayRecords = records.filter { !$0.isWeekend }
        let weekendRecords = records.filter { $0.isWeekend }
        let socialJetlag: Double
        if !weekdayRecords.isEmpty && !weekendRecords.isEmpty {
            let wdMidSleep = weekdayRecords.map {
                CoachEngine.circularMidSleep(bed: $0.bedtimeHour, wake: $0.wakeupHour)
            }.reduce(0, +) / Double(weekdayRecords.count)
            let weMidSleep = weekendRecords.map {
                CoachEngine.circularMidSleep(bed: $0.bedtimeHour, wake: $0.wakeupHour)
            }.reduce(0, +) / Double(weekendRecords.count)
            socialJetlag = abs(CoachEngine.circularDiffMinutes(actual: weMidSleep, target: wdMidSleep))
        } else {
            socialJetlag = 0
        }
        return SleepStats(
            meanAcrophase: meanAcro,
            stdAcrophase: 0.5,
            stdBedtime: 0.3,
            meanAmplitude: 0.3,
            rhythmStability: 0.7,
            socialJetlag: socialJetlag,
            weekdayAmp: 0.3,
            weekendAmp: 0.3,
            ampDrop: 0,
            meanSleepDuration: meanDur,
            meanR2: 0.8,
            sri: 80
        )
    }

    // MARK: - General Health: Delayed Phase

    @Test("Single record at 5am bed → delayedPhase (not maintenance or healthy)")
    func testDelayedPhaseFromSingleRecord() {
        let records = [makeRecord(day: 0, bedHour: 5.0, wakeHour: 12.0, duration: 7.0)]
        let stats = makeStats(from: records)
        // acrophase for 5am-12pm sleep: activity peaks ~20:30h
        let statsWithHighAcro = SleepStats(
            meanAcrophase: 21.0, stdAcrophase: 0, stdBedtime: 0,
            meanAmplitude: 0.3, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.3, weekendAmp: 0.3, ampDrop: 0,
            meanSleepDuration: 7.0, meanR2: 0.8, sri: 0
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: statsWithHighAcro,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .delayedPhase, "5am bedtime should trigger delayedPhase, got \(insight.issueKey)")
    }

    @Test("7 nights at 23:00 bed / 07:00 wake → maintenance")
    func testNormalScheduleMaintenance() {
        let records = (0..<7).map { i in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: 23.0, wakeHour: 7.0, duration: 8.0)
        }
        let stats = makeStats(from: records)
        let statsNormal = SleepStats(
            meanAcrophase: 15.0, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.4, rhythmStability: 0.85, socialJetlag: 10,
            weekdayAmp: 0.4, weekendAmp: 0.4, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.9, sri: 88
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: statsNormal,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .maintenance, "Healthy 23:00-07:00 schedule should give maintenance, got \(insight.issueKey)")
        #expect(insight.severity == .info)
    }

    @Test("midSleep >90 min late triggers delayedPhase even without acrophase signal")
    func testDelayedPhaseMidSleepOffset() {
        // Bed 02:00, wake 10:00 — midSleep=06:00, vs goal midSleep 03:00 → +3h late
        let records = (0..<7).map { i in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: 2.0, wakeHour: 10.0, duration: 8.0)
        }
        let stats = SleepStats(
            meanAcrophase: 17.0, stdAcrophase: 0.4, stdBedtime: 0.3,
            meanAmplitude: 0.35, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.35, weekendAmp: 0.35, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.85, sri: 85
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .delayedPhase, "Bed at 02:00 should trigger delayedPhase, got \(insight.issueKey)")
    }

    @Test("No false 'healthy' for delayed pattern")
    func testNoFalseHealthyForDelayedPattern() {
        // This is the exact user case: 5:00-12:00 + 14:00-16:00
        let records = [makeRecord(day: 0, bedHour: 5.0, wakeHour: 12.0, duration: 7.0)]
        let delayedStats = SleepStats(
            meanAcrophase: 20.5, stdAcrophase: 0, stdBedtime: 0,
            meanAmplitude: 0.3, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.3, weekendAmp: 0.3, ampDrop: 0,
            meanSleepDuration: 9.6, meanR2: 0.8, sri: 0
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: delayedStats,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey != .maintenance,
                "5am bedtime must NOT return maintenance/healthy, got \(insight.issueKey)")
        #expect(insight.issueKey != .insufficientData,
                "Should not be insufficientData with 1 record")
    }

    // MARK: - General Health: Other Issues

    @Test("Social jetlag >60 min triggers socialJetlag")
    func testSocialJetlag() {
        let weekdays = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 23.0, wakeHour: 7.0,
                       duration: 8.0, isWeekend: false)
        }
        let weekends = (0..<2).map { i in
            makeRecord(day: i + 5, daysAgo: 1 - i, bedHour: 1.0, wakeHour: 9.5,
                       duration: 8.5, isWeekend: true)
        }
        let records = weekdays + weekends
        let statsWithJetlag = SleepStats(
            meanAcrophase: 15.5, stdAcrophase: 0.5, stdBedtime: 0.5,
            meanAmplitude: 0.35, rhythmStability: 0.75, socialJetlag: 90,
            weekdayAmp: 0.36, weekendAmp: 0.34, ampDrop: 3,
            meanSleepDuration: 8.0, meanR2: 0.82, sri: 72
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: statsWithJetlag,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .socialJetlag, "90 min social jetlag should trigger socialJetlag, got \(insight.issueKey)")
    }

    @Test("High schedule variability → irregularSchedule")
    func testIrregularSchedule() {
        let bedHours: [Double] = [22.0, 0.5, 23.0, 2.0, 21.5, 1.5, 23.5]
        let records = bedHours.enumerated().map { i, bed in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: bed,
                       wakeHour: bed.truncatingRemainder(dividingBy: 24) + 8, duration: 8.0)
        }
        let irregularStats = SleepStats(
            meanAcrophase: 14.5, stdAcrophase: 1.5, stdBedtime: 1.2,
            meanAmplitude: 0.28, rhythmStability: 0.45, socialJetlag: 15,
            weekdayAmp: 0.3, weekendAmp: 0.26, ampDrop: 13,
            meanSleepDuration: 8.0, meanR2: 0.6, sri: 55
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: irregularStats,
            goal: .generalHealthDefault, consistency: nil
        )
        // Should be irregular OR social jetlag — not maintenance
        #expect(insight.issueKey != .maintenance, "High variability should not give maintenance")
        #expect(insight.issueKey != .insufficientData)
    }

    @Test("Averaging 5.5h sleep → insufficientDuration")
    func testInsufficientDuration() {
        let records = (0..<7).map { i in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: 23.5, wakeHour: 5.0, duration: 5.5)
        }
        let shortStats = SleepStats(
            meanAcrophase: 14.5, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.35, rhythmStability: 0.75, socialJetlag: 10,
            weekdayAmp: 0.36, weekendAmp: 0.34, ampDrop: 2,
            meanSleepDuration: 5.5, meanR2: 0.85, sri: 82
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: shortStats,
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .insufficientDuration,
                "5.5h average should give insufficientDuration, got \(insight.issueKey)")
        #expect(insight.severity >= .moderate)
    }

    @Test("Good duration but late timing → sufficientButMisaligned")
    func testSufficientButMisaligned() {
        // Bed 02:00, wake 10:00 — 8h, midSleep = 06:00, goal midSleep ≈ 03:00 → ~3h late
        // But acrophase stays within non-delayed threshold (put it at 17h — not >18.5)
        let records = (0..<7).map { i in
            makeRecord(day: i, daysAgo: 6 - i, bedHour: 1.5, wakeHour: 9.5, duration: 8.0)
        }
        let stats = SleepStats(
            meanAcrophase: 17.0, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.38, rhythmStability: 0.82, socialJetlag: 5,
            weekdayAmp: 0.38, weekendAmp: 0.38, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.9, sri: 90
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil
        )
        // midSleep=05:30, goal midSleep=03:00 → ~150 min late → delayedPhase fires first
        // OR sufficientButMisaligned if below the 90min threshold at the midSleep level
        #expect(insight.issueKey != .maintenance,
                "Late but sufficient sleep should not be 'maintenance'")
    }

    @Test("No records → insufficientData")
    func testNoRecords() {
        let insight = CoachEngine.evaluate(
            records: [], stats: SleepStats(),
            goal: .generalHealthDefault, consistency: nil
        )
        #expect(insight.issueKey == .insufficientData)
        #expect(insight.severity == .info)
    }

    // MARK: - Shift Work

    @Test("Shift worker sleeping 09:00-15:10 vs goal 08:30-15:30 → maintenance")
    func testShiftWorkAligned() {
        let shiftGoal = SleepGoal(
            mode: .shiftWork,
            targetBedHour: 8.5,    // 08:30
            targetWakeHour: 15.5,  // 15:30
            targetDuration: 7.0,
            toleranceMinutes: 60
        )
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 9.0, wakeHour: 15.17, duration: 6.17)
        }
        let stats = SleepStats(
            meanAcrophase: 12.5, stdAcrophase: 0.4, stdBedtime: 0.3,
            meanAmplitude: 0.33, rhythmStability: 0.7, socialJetlag: 0,
            weekdayAmp: 0.33, weekendAmp: 0.33, ampDrop: 0,
            meanSleepDuration: 6.17, meanR2: 0.8, sri: 80
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: shiftGoal, consistency: nil
        )
        // 09:00 vs 08:30 = 30 min off; tolerance=60 min → aligned
        #expect(insight.issueKey == .maintenance || insight.issueKey == .insufficientDuration,
                "Shift worker within tolerance should be maintenance or insufficientDuration, got \(insight.issueKey)")
        // Critically: must NOT say offTargetForShift, irregularSchedule
        #expect(insight.issueKey != .offTargetForShift,
                "Shift worker within tolerance must not be offTargetForShift")
        #expect(insight.issueKey != .delayedPhase,
                "Shift worker must not be labeled as delayed — they are working nights")
    }

    @Test("Shift worker sleeping 11:00-17:00 vs goal 08:30-15:30 → offTargetForShift")
    func testShiftWorkOffTarget() {
        let shiftGoal = SleepGoal(
            mode: .shiftWork,
            targetBedHour: 8.5,
            targetWakeHour: 15.5,
            targetDuration: 7.0,
            toleranceMinutes: 60
        )
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 11.0, wakeHour: 17.0, duration: 6.0)
        }
        let stats = SleepStats(
            meanAcrophase: 14.5, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.32, rhythmStability: 0.72, socialJetlag: 0,
            weekdayAmp: 0.32, weekendAmp: 0.32, ampDrop: 0,
            meanSleepDuration: 6.0, meanR2: 0.8, sri: 82
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: shiftGoal, consistency: nil
        )
        // 11:00 vs 08:30 = 150 min off, beyond 60 min tolerance
        #expect(insight.issueKey == .offTargetForShift,
                "Should be offTargetForShift, got \(insight.issueKey)")
    }

    // MARK: - Custom Schedule

    @Test("Custom schedule on target → maintenance")
    func testCustomScheduleAligned() {
        let customGoal = SleepGoal(
            mode: .customSchedule,
            targetBedHour: 1.0,
            targetWakeHour: 9.0,
            targetDuration: 8.0,
            toleranceMinutes: 60
        )
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 1.25, wakeHour: 9.25, duration: 8.0)
        }
        let stats = SleepStats(
            meanAcrophase: 17.5, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.35, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.35, weekendAmp: 0.35, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.87, sri: 84
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: customGoal, consistency: nil
        )
        // 1:15 vs goal 1:00 = 15 min off, well within tolerance
        #expect(insight.issueKey == .maintenance,
                "Custom schedule on target should give maintenance, got \(insight.issueKey)")
    }

    @Test("Custom schedule 2h off target → offTargetForCustomSchedule")
    func testCustomScheduleOffTarget() {
        let customGoal = SleepGoal(
            mode: .customSchedule,
            targetBedHour: 22.0,
            targetWakeHour: 6.0,
            targetDuration: 8.0,
            toleranceMinutes: 60
        )
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 0.5, wakeHour: 8.5, duration: 8.0)
        }
        let stats = SleepStats(
            meanAcrophase: 16.0, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.36, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.36, weekendAmp: 0.36, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.88, sri: 85
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: customGoal, consistency: nil
        )
        // 00:30 vs 22:00 = 150 min late, beyond tolerance
        #expect(insight.issueKey == .offTargetForCustomSchedule,
                "2.5h off custom target should give offTargetForCustomSchedule, got \(insight.issueKey)")
    }

    // MARK: - Rephase

    @Test("Sleep 04:20-11:30, rephase target 01:00-09:00 → rephaseInProgress")
    func testRephaseInProgress() {
        let rephaseGoal = SleepGoal(
            mode: .rephase,
            targetBedHour: 1.0,
            targetWakeHour: 9.0,
            targetDuration: 8.0,
            toleranceMinutes: 60,
            rephaseStepMinutes: 30
        )
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 4.33, wakeHour: 11.5, duration: 7.17)
        }
        let stats = SleepStats(
            meanAcrophase: 19.0, stdAcrophase: 0.4, stdBedtime: 0.3,
            meanAmplitude: 0.32, rhythmStability: 0.7, socialJetlag: 0,
            weekdayAmp: 0.32, weekendAmp: 0.32, ampDrop: 0,
            meanSleepDuration: 7.17, meanR2: 0.8, sri: 80
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: rephaseGoal, consistency: nil
        )
        // Wake at 11:30 vs target 09:00 = +150 min → step=30 → 150 > 30*2=60 → rephaseInProgress
        #expect(insight.issueKey == .rephaseInProgress,
                "150 min behind target should give rephaseInProgress, got \(insight.issueKey)")
    }

    @Test("Rephase nearly at target (within 1 step) → maintenance")
    func testRephaseNearTarget() {
        let rephaseGoal = SleepGoal(
            mode: .rephase,
            targetBedHour: 23.0,
            targetWakeHour: 7.0,
            targetDuration: 8.0,
            toleranceMinutes: 60,
            rephaseStepMinutes: 30
        )
        // Wake at 07:20 vs target 07:00 = +20 min → within 2 steps (60 min)
        let records = (0..<5).map { i in
            makeRecord(day: i, daysAgo: 4 - i, bedHour: 23.33, wakeHour: 7.33, duration: 8.0)
        }
        let stats = SleepStats(
            meanAcrophase: 15.3, stdAcrophase: 0.3, stdBedtime: 0.2,
            meanAmplitude: 0.38, rhythmStability: 0.82, socialJetlag: 5,
            weekdayAmp: 0.38, weekendAmp: 0.38, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.88, sri: 86
        )
        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: rephaseGoal, consistency: nil
        )
        // 20 min delay, step=30, threshold=60 min → not rephaseInProgress
        #expect(insight.issueKey != .rephaseInProgress,
                "Only 20 min behind should not be rephaseInProgress, got \(insight.issueKey)")
    }

    // MARK: - CircadianAssessment

    @Test("assess() returns correct midSleep deviation sign for late sleep")
    func testAssessmentMidSleepDeviationLate() {
        // Bed 02:00, wake 10:00 → midSleep = 06:00; goal midSleep = 03:00 → +3h = +180 min
        let records = [makeRecord(day: 0, bedHour: 2.0, wakeHour: 10.0, duration: 8.0)]
        let stats = SleepStats(
            meanAcrophase: 17.0, stdAcrophase: 0, stdBedtime: 0,
            meanAmplitude: 0.35, rhythmStability: 0.8, socialJetlag: 0,
            weekdayAmp: 0.35, weekendAmp: 0.35, ampDrop: 0,
            meanSleepDuration: 8.0, meanR2: 0.85, sri: 0
        )
        let assessment = CoachEngine.assess(records: records, stats: stats,
                                             goal: .generalHealthDefault)
        // midSleep = 06:00, goal = 03:00 → +180 min
        #expect(assessment.midSleepDeviationMinutes > 0,
                "Late sleep should give positive midSleep deviation")
        #expect(assessment.midSleepDeviationMinutes > 120,
                "Should be significantly positive (>120 min), got \(assessment.midSleepDeviationMinutes)")
    }

    @Test("assess() detects split sleep when significant daytime sleep present")
    func testAssessmentSplitSleepDetected() {
        // Main sleep 05:00-12:00, then nap 14:00-16:00
        // Day has sleep at hours 5,6,7,8,9,10,11 and 14,15
        let hourlyActivity = (0..<24).map { h -> HourlyActivity in
            let sleeping = (h >= 5 && h < 12) || (h >= 14 && h < 16)
            return HourlyActivity(hour: h, activity: sleeping ? 0.1 : 0.9)
        }
        let record = SleepRecord(
            day: 0, date: Date(), isWeekend: false,
            bedtimeHour: 5.0, wakeupHour: 12.0, sleepDuration: 9.0,
            phases: [], hourlyActivity: hourlyActivity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 20, period: 24, r2: 0.7)
        )
        let stats = SleepStats(
            meanAcrophase: 20.0, stdAcrophase: 0, stdBedtime: 0,
            meanAmplitude: 0.3, rhythmStability: 0.7, socialJetlag: 0,
            weekdayAmp: 0.3, weekendAmp: 0.3, ampDrop: 0,
            meanSleepDuration: 9.0, meanR2: 0.7, sri: 0
        )
        let assessment = CoachEngine.assess(records: [record, record, record],
                                             stats: stats, goal: .generalHealthDefault)
        #expect(assessment.splitSleepDaytimeMinutes > 0,
                "Should detect daytime sleep, got \(assessment.splitSleepDaytimeMinutes) min")
    }

    @Test("assess() handles single record without crashing")
    func testAssessmentSingleRecord() {
        let record = makeRecord(day: 0, bedHour: 23.0, wakeHour: 7.0, duration: 8.0)
        let stats = SleepStats(meanSleepDuration: 8.0)
        let assessment = CoachEngine.assess(records: [record], stats: stats,
                                             goal: .generalHealthDefault)
        #expect(assessment.recordCount == 1)
        #expect(assessment.meanDurationHours.isFinite)
        #expect(assessment.midSleepDeviationMinutes.isFinite)
    }

    // MARK: - Circular Math

    @Test("circularDiffMinutes: actual later than target → positive")
    func testCircularDiffPositive() {
        let diff = CoachEngine.circularDiffMinutes(actual: 4.0, target: 2.0) // 2h later
        #expect(diff > 0)
        #expect(abs(diff - 120) < 1)
    }

    @Test("circularDiffMinutes: midnight wrap (actual=01:00, target=23:00) → +120 not -1320")
    func testCircularDiffMidnightWrap() {
        // 01:00 is 2h after 23:00
        let diff = CoachEngine.circularDiffMinutes(actual: 1.0, target: 23.0)
        #expect(diff > 0, "Should be positive (actual is later)")
        #expect(abs(diff - 120) < 1, "Should be ~120 min, got \(diff)")
    }

    @Test("circularMidSleep: midnight-crossing window gives correct midpoint")
    func testCircularMidSleepMidnightCross() {
        // Bed 23:00, wake 07:00 → midSleep = 03:00
        let mid = CoachEngine.circularMidSleep(bed: 23.0, wake: 7.0)
        #expect(abs(mid - 3.0) < 0.1, "Midpoint of 23:00-07:00 should be ~03:00, got \(mid)")
    }

    @Test("CoachSeverity is Comparable")
    func testSeverityComparable() {
        #expect(CoachSeverity.info < CoachSeverity.mild)
        #expect(CoachSeverity.mild < CoachSeverity.moderate)
        #expect(CoachSeverity.moderate < CoachSeverity.urgent)
    }

    @Test("SleepGoal.targetMidSleepHour computed correctly for default goal")
    func testTargetMidSleepHour() {
        // Default: bed 23:00, wake 07:00 → midSleep = 03:00
        let mid = SleepGoal.generalHealthDefault.targetMidSleepHour
        #expect(abs(mid - 3.0) < 0.1, "generalHealthDefault midSleep should be ~03:00, got \(mid)")
    }
}
