import Foundation
import Testing
@testable import SpiralKit

@Suite("Coach Context Tests")
struct CoachContextTests {

    // MARK: - Helpers

    private func makeRecords(count: Int, bedtime: Double = 23.0, wakeup: Double = 7.0) -> [SleepRecord] {
        (0..<count).map { day in
            let dur: Double = {
                let d = wakeup - bedtime
                return d >= 0 ? d : d + 24.0
            }()
            return SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: bedtime, wakeupHour: wakeup, sleepDuration: dur,
                phases: [],
                hourlyActivity: (0..<24).map { hour in
                    let h = Double(hour)
                    let isAsleep: Bool
                    if bedtime < wakeup {
                        isAsleep = h >= bedtime && h < wakeup
                    } else {
                        isAsleep = h >= bedtime || h < wakeup
                    }
                    return HourlyActivity(hour: hour, activity: isAsleep ? 0.0 : 0.8)
                },
                cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0, period: 24, r2: 0.8)
            )
        }
    }

    private func defaultStats() -> SleepStats {
        SleepStatistics.calculateStats(makeRecords(count: 7))
    }

    private func workBlock() -> ContextBlock {
        ContextBlock(type: .work, label: "Office", startHour: 9.0, endHour: 17.0,
                     activeDays: ContextBlock.weekdays)
    }

    // MARK: - Tests

    @Test("Coach produces sleepOverlapsContext when overlap exists")
    func coachDetectsOverlap() {
        let records = makeRecords(count: 7, bedtime: 23.0, wakeup: 7.0)
        let stats = SleepStatistics.calculateStats(records)
        let block = workBlock()

        // Create a conflict manually
        let conflict = ScheduleConflict(
            type: .sleepOverlapsBlock,
            blockID: block.id,
            blockType: .work,
            blockLabel: "Office",
            day: 0,
            overlapMinutes: 60,
            sleepEndHour: 8.0,
            blockStartHour: 7.0
        )

        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil,
            contextBlocks: [block], conflicts: [conflict]
        )

        #expect(insight.issueKey == .sleepOverlapsContext,
                "Should produce overlap context insight, got \(insight.issueKey)")
    }

    @Test("Urgent circadian issue takes priority over mild conflict")
    func circadianPriorityOverMildConflict() {
        // Delayed phase records: bedtime 3am, wake 11am → midSleep very late
        let records = makeRecords(count: 7, bedtime: 3.0, wakeup: 11.0)
        let stats = SleepStatistics.calculateStats(records)
        let block = workBlock()

        // Mild conflict: too close
        let conflict = ScheduleConflict(
            type: .sleepTooCloseToBlockStart,
            blockID: block.id,
            blockType: .work,
            blockLabel: "Office",
            day: 0,
            overlapMinutes: 30,
            sleepEndHour: 8.5,
            blockStartHour: 9.0
        )

        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil,
            contextBlocks: [block], conflicts: [conflict]
        )

        // Delayed phase is moderate, tooClose is mild → delayed phase wins
        #expect(insight.issueKey == .delayedPhase,
                "Moderate delayedPhase should beat mild conflict, got \(insight.issueKey)")
    }

    @Test("Conflict insight beats maintenance")
    func conflictOverMaintenance() {
        // Normal healthy records → base insight should be maintenance
        let records = makeRecords(count: 7, bedtime: 23.0, wakeup: 7.0)
        let stats = SleepStatistics.calculateStats(records)
        let block = workBlock()

        // Add a tooClose conflict
        let conflict = ScheduleConflict(
            type: .sleepTooCloseToBlockStart,
            blockID: block.id,
            blockType: .work,
            blockLabel: "Office",
            day: 0,
            overlapMinutes: 30,
            sleepEndHour: 8.5,
            blockStartHour: 9.0
        )

        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil,
            contextBlocks: [block], conflicts: [conflict]
        )

        #expect(insight.issueKey == .sleepTooCloseToContext,
                "Conflict should beat maintenance, got \(insight.issueKey)")
    }

    @Test("shiftWork mode suppresses tooClose messages")
    func shiftWorkSuppressesTooClose() {
        let records = makeRecords(count: 7, bedtime: 23.0, wakeup: 7.0)
        let stats = SleepStatistics.calculateStats(records)
        let block = workBlock()

        let shiftGoal = SleepGoal(
            mode: .shiftWork,
            targetBedHour: 23.0, targetWakeHour: 7.0,
            targetDuration: 8.0, toleranceMinutes: 60
        )

        // Only tooClose conflict (no overlap)
        let conflict = ScheduleConflict(
            type: .sleepTooCloseToBlockStart,
            blockID: block.id,
            blockType: .work,
            blockLabel: "Office",
            day: 0,
            overlapMinutes: 30,
            sleepEndHour: 8.5,
            blockStartHour: 9.0
        )

        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: shiftGoal, consistency: nil,
            contextBlocks: [block], conflicts: [conflict]
        )

        // shiftWork filters out tooClose → should fall back to base insight
        #expect(insight.issueKey != .sleepTooCloseToContext,
                "shiftWork mode should suppress tooClose, got \(insight.issueKey)")
    }

    @Test("No blocks → standard insight, no context issues")
    func noBlocksNoContextInsights() {
        let records = makeRecords(count: 7, bedtime: 23.0, wakeup: 7.0)
        let stats = SleepStatistics.calculateStats(records)

        let insight = CoachEngine.evaluate(
            records: records, stats: stats,
            goal: .generalHealthDefault, consistency: nil,
            contextBlocks: [], conflicts: []
        )

        // Should be standard maintenance or similar, never context keys
        let contextKeys: [CoachIssueKey] = [.sleepOverlapsContext, .sleepTooCloseToContext, .daytimeSleepConsumesContext]
        #expect(!contextKeys.contains(insight.issueKey),
                "Without blocks, should never produce context insights, got \(insight.issueKey)")
    }
}
