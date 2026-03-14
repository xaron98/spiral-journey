import Foundation
import Testing
@testable import SpiralKit

@Suite("ScheduleConflict Tests")
struct ScheduleConflictTests {

    // MARK: - Helpers

    /// Create a SleepRecord for a specific day with given bed/wake hours.
    /// weekday: Calendar weekday (1=Sun..7=Sat). Default 3 = Tuesday (weekday).
    private func makeRecord(
        day: Int = 0,
        bedtime: Double = 23.0,
        wakeup: Double = 7.0,
        sleepDuration: Double? = nil,
        weekday: Int = 3
    ) -> SleepRecord {
        let dur = sleepDuration ?? {
            let d = wakeup - bedtime
            return d >= 0 ? d : d + 24.0
        }()

        // Build hourly activity: asleep hours have activity 0.0, awake hours 0.8
        let activity: [HourlyActivity] = (0..<24).map { hour in
            let h = Double(hour)
            let isAsleep: Bool
            if bedtime < wakeup {
                isAsleep = h >= bedtime && h < wakeup
            } else {
                isAsleep = h >= bedtime || h < wakeup
            }
            return HourlyActivity(hour: hour, activity: isAsleep ? 0.0 : 0.8)
        }

        // Create a date for the given weekday
        var cal = Calendar.current
        cal.firstWeekday = 1  // Sunday = 1
        let baseDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 8 + weekday))!
        // March 8 2026 is Sunday, so +weekday gives the right day

        return SleepRecord(
            day: day, date: baseDate, isWeekend: weekday == 1 || weekday == 7,
            bedtimeHour: bedtime, wakeupHour: wakeup, sleepDuration: dur,
            phases: [],
            hourlyActivity: activity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
        )
    }

    private func workBlock(
        start: Double = 9.0,
        end: Double = 17.0,
        days: UInt8 = ContextBlock.weekdays,
        enabled: Bool = true
    ) -> ContextBlock {
        ContextBlock(type: .work, label: "Office", startHour: start, endHour: end,
                     activeDays: days, isEnabled: enabled)
    }

    private func studyBlock(
        start: Double = 18.0,
        end: Double = 21.0,
        days: UInt8 = ContextBlock.weekdays
    ) -> ContextBlock {
        ContextBlock(type: .study, label: "Evening class", startHour: start, endHour: end,
                     activeDays: days)
    }

    // MARK: - Overlap Tests

    @Test("Sleep 23:00-08:00 overlaps work 07:00-15:00")
    func sleepOverlapsWork() {
        let record = makeRecord(bedtime: 23.0, wakeup: 8.0, weekday: 3)  // Tuesday
        let block = workBlock(start: 7.0, end: 15.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])

        #expect(!conflicts.isEmpty, "Should detect overlap")
        #expect(conflicts.first?.type == .sleepOverlapsBlock)
        #expect(conflicts.first!.overlapMinutes > 15, "Overlap should be > noise floor")
    }

    @Test("Sleep 23:00-06:30 with work at 07:00 → too close (30min < 60min buffer)")
    func sleepTooCloseToWork() {
        let record = makeRecord(bedtime: 23.0, wakeup: 6.5, weekday: 3)
        let block = workBlock(start: 7.0, end: 15.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])

        #expect(!conflicts.isEmpty, "Should detect too-close conflict")
        #expect(conflicts.first?.type == .sleepTooCloseToBlockStart)
    }

    @Test("Sleep 23:00-06:00 with work at 08:00 → sufficient buffer, no conflict")
    func sufficientBufferNoConflict() {
        let record = makeRecord(bedtime: 23.0, wakeup: 6.0, weekday: 3)
        let block = workBlock(start: 8.0, end: 16.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])

        // Gap = 120 min >= 60 min buffer → no conflict
        let tooClose = conflicts.filter { $0.type == .sleepTooCloseToBlockStart }
        #expect(tooClose.isEmpty, "120 min gap should not trigger too-close")
    }

    @Test("Siesta 14:00-15:30 during work 09:00-17:00")
    func daytimeSleepInOperationalWindow() {
        // Record with nap: asleep hours include 14 and 15
        var activity = (0..<24).map { HourlyActivity(hour: $0, activity: 0.8) }
        // Mark 23-7 as main sleep + 14-15 as nap
        for h in [23, 0, 1, 2, 3, 4, 5, 6, 14, 15] {
            activity[h] = HourlyActivity(hour: h, activity: 0.0)
        }

        var cal = Calendar.current
        cal.firstWeekday = 1
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 11))!  // Wednesday

        let record = SleepRecord(
            day: 0, date: date, isWeekend: false,
            bedtimeHour: 23.0, wakeupHour: 7.0, sleepDuration: 8.0,
            phases: [], hourlyActivity: activity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
        )

        let block = workBlock(start: 9.0, end: 17.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])

        let daytimeConflicts = conflicts.filter { $0.type == .daytimeSleepConsumesWindow }
        #expect(!daytimeConflicts.isEmpty, "Should detect daytime sleep in work window")
    }

    @Test("Short nap 20 min during work → no conflict (below threshold)")
    func shortNapNoConflict() {
        // Only 1 hour partially asleep (activity 0.4 → partial, not enough for 45 min)
        var activity = (0..<24).map { HourlyActivity(hour: $0, activity: 0.8) }
        for h in [23, 0, 1, 2, 3, 4, 5, 6] { activity[h] = HourlyActivity(hour: h, activity: 0.0) }
        // Hour 13 is partially sleepy but not fully asleep
        activity[13] = HourlyActivity(hour: 13, activity: 0.4)

        var cal = Calendar.current
        cal.firstWeekday = 1
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 11))!

        let record = SleepRecord(
            day: 0, date: date, isWeekend: false,
            bedtimeHour: 23.0, wakeupHour: 7.0, sleepDuration: 8.0,
            phases: [], hourlyActivity: activity,
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
        )

        let block = workBlock(start: 9.0, end: 17.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])

        let daytime = conflicts.filter { $0.type == .daytimeSleepConsumesWindow }
        #expect(daytime.isEmpty, "Partial hour should not reach 45 min threshold")
    }

    // MARK: - Filtering Tests

    @Test("Disabled block is skipped")
    func disabledBlockSkipped() {
        let record = makeRecord(bedtime: 23.0, wakeup: 8.0, weekday: 3)
        let block = workBlock(start: 7.0, end: 15.0, enabled: false)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])
        #expect(conflicts.isEmpty, "Disabled block should not generate conflicts")
    }

    @Test("Block Mon-Fri, record on Saturday → no conflict")
    func weekdayFiltering() {
        let record = makeRecord(bedtime: 23.0, wakeup: 8.0, weekday: 7)  // Saturday
        let block = workBlock(start: 7.0, end: 15.0, days: ContextBlock.weekdays)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [block])
        #expect(conflicts.isEmpty, "Weekend record should not conflict with weekday-only block")
    }

    @Test("No blocks → no conflicts")
    func noBlocksNoConflicts() {
        let record = makeRecord(bedtime: 23.0, wakeup: 8.0)
        let conflicts = ScheduleConflictDetector.detect(records: [record], blocks: [])
        #expect(conflicts.isEmpty)
    }

    @Test("No records → no conflicts")
    func noRecordsNoConflicts() {
        let block = workBlock()
        let conflicts = ScheduleConflictDetector.detect(records: [], blocks: [block])
        #expect(conflicts.isEmpty)
    }

    // MARK: - Circular Math Tests

    @Test("Overnight block 22:00-06:00 overlap with sleep 23:00-07:00")
    func overnightBlockOverlap() {
        let overlap = ScheduleConflictDetector.circularOverlapMinutes(
            sleepStart: 23.0, sleepEnd: 7.0,
            blockStart: 22.0, blockEnd: 6.0
        )
        // Sleep 23-07 (8h) overlaps block 22-06 (8h) from 23:00 to 06:00 = 7h = 420 min
        #expect(overlap >= 360, "Overnight overlap should be >= 6h (360 min), got \(overlap)")
    }

    @Test("Gap calculation wraps correctly at midnight")
    func gapMidnightWrap() {
        // Wake at 23:00, work starts at 01:00 → gap should be 120 min
        let gap = ScheduleConflictDetector.circularGapMinutes(from: 23.0, to: 1.0)
        #expect(abs(gap - 120.0) < 1.0, "Gap should be ~120 min, got \(gap)")
    }

    @Test("Gap calculation forward direction")
    func gapForward() {
        // Wake at 7:00, work at 9:00 → gap = 120 min
        let gap = ScheduleConflictDetector.circularGapMinutes(from: 7.0, to: 9.0)
        #expect(abs(gap - 120.0) < 1.0)
    }

    // MARK: - ContextBlock Model Tests

    @Test("ContextBlock activeDays bitmask Mon-Fri")
    func activeDaysBitmask() {
        let block = ContextBlock(activeDays: ContextBlock.weekdays)
        // Sunday = 1, Monday = 2, ..., Friday = 6, Saturday = 7
        #expect(!block.isActive(weekday: 1), "Sunday should be inactive")
        #expect(block.isActive(weekday: 2), "Monday should be active")
        #expect(block.isActive(weekday: 3), "Tuesday should be active")
        #expect(block.isActive(weekday: 6), "Friday should be active")
        #expect(!block.isActive(weekday: 7), "Saturday should be inactive")
    }

    @Test("ContextBlock durationHours handles overnight")
    func durationOvernight() {
        let block = ContextBlock(startHour: 22.0, endHour: 6.0)
        #expect(abs(block.durationHours - 8.0) < 0.01, "22:00-06:00 should be 8h")
    }

    @Test("ContextBlock durationHours normal daytime")
    func durationNormal() {
        let block = ContextBlock(startHour: 9.0, endHour: 17.0)
        #expect(abs(block.durationHours - 8.0) < 0.01, "09:00-17:00 should be 8h")
    }

    @Test("ContextBlock timeRangeString format")
    func timeRangeFormat() {
        let block = ContextBlock(startHour: 9.0, endHour: 17.5)
        #expect(block.timeRangeString == "09:00–17:30")
    }

    @Test("All block types have SF symbols")
    func allTypesHaveSymbols() {
        for type in ContextBlockType.allCases {
            #expect(!type.sfSymbol.isEmpty, "\(type) should have an SF Symbol")
            #expect(!type.hexColor.isEmpty, "\(type) should have a hex color")
            #expect(!type.localizationKey.isEmpty, "\(type) should have a localization key")
        }
    }
}
