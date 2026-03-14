import Testing
@testable import SpiralKit
import Foundation

@Suite("NapOptimizer Context-Aware Tests")
struct NapOptimizerContextTests {

    // MARK: - Helpers

    /// Create records that produce high enough Process S for a nap recommendation.
    /// Short sleep (5h) for 3 consecutive days → S builds up.
    private func makeDebtRecords() -> [SleepRecord] {
        (0..<3).map { day in
            SleepRecord(
                day: day,
                date: Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date(),
                isWeekend: false,
                bedtimeHour: 1.0,       // late bedtime
                wakeupHour: 6.0,        // early wake
                sleepDuration: 5.0,     // only 5h
                phases: [],
                hourlyActivity: (0..<24).map { h in
                    // Asleep from 01:00-06:00 (hours 1-5), awake rest
                    let active = (h >= 1 && h <= 5) ? 0.05 : 0.85
                    return HourlyActivity(hour: h, activity: active)
                },
                cosinor: .empty,
                driftMinutes: 0
            )
        }
    }

    private func makeWorkBlock(start: Double, end: Double) -> ContextBlock {
        ContextBlock(
            type: .work,
            label: "Work",
            startHour: start,
            endHour: end,
            activeDays: ContextBlock.everyDay,
            isEnabled: true
        )
    }

    // MARK: - Tests

    @Test("No context blocks → identical to base recommend()")
    func noBlocksIdentical() {
        let records = makeDebtRecords()
        let base = NapOptimizer.recommend(records: records, wakeHour: 6.0)
        let context = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: [],
            weekday: 2 // Monday
        )

        // Both should return the same recommendation (or both nil)
        #expect(base?.suggestedStart == context?.suggestedStart)
        #expect(base?.duration == context?.duration)
    }

    @Test("Nap doesn't conflict with block → returns base unchanged")
    func noConflict() {
        let records = makeDebtRecords()
        // Work block 08:00-12:00, nap window is 12:00-16:00 → no overlap
        let blocks = [makeWorkBlock(start: 8.0, end: 12.0)]

        let result = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: blocks,
            weekday: 2
        )

        #expect(result != nil)
        // Should NOT be contextAdjusted since there's no conflict
        if let r = result {
            #expect(r.reason != .contextAdjusted)
        }
    }

    @Test("Block on different weekday → no adjustment")
    func differentWeekday() {
        let records = makeDebtRecords()
        // Block active only on Sunday (bit 0)
        var block = makeWorkBlock(start: 13.0, end: 17.0)
        block.activeDays = 0b0000001  // Sunday only

        let result = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: [block],
            weekday: 2  // Monday
        )

        #expect(result != nil)
        if let r = result {
            #expect(r.reason != .contextAdjusted)
        }
    }

    @Test("Nap conflicts with work block → adjusted or nil")
    func napConflictsWithWork() {
        let records = makeDebtRecords()
        // Work block covers most of the nap window: 12:00-17:00
        let blocks = [makeWorkBlock(start: 12.0, end: 17.0)]

        let result = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: blocks,
            weekday: 2
        )

        // Should either be adjusted (moved before 12:00) or nil
        if let r = result {
            #expect(r.reason == .contextAdjusted)
            // Adjusted nap should end before the block starts
            let napEnd = r.suggestedStart + Double(r.duration) / 60.0
            #expect(napEnd <= 12.0 + 0.1)  // small tolerance
        }
        // nil is also acceptable if no slot fits
    }

    @Test("90-min nap overlapping block → reduced to 20-min if fits")
    func longNapReducedToShort() {
        let records = makeDebtRecords()
        // Work block 15:00-17:00 — a 90-min nap at 14:00 would extend to 15:30 (overlap)
        // But a 20-min nap at 14:00 would end at 14:20 (no overlap)
        let blocks = [makeWorkBlock(start: 15.0, end: 17.0)]

        let base = NapOptimizer.recommend(records: records, wakeHour: 6.0)
        let context = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: blocks,
            weekday: 2
        )

        // If base was 90 min and at 14:00, context should reduce to 20 min
        if let b = base, b.duration == 90, let c = context {
            #expect(c.duration == 20 || c.reason == .contextAdjusted)
        }
    }

    @Test("Disabled block is ignored")
    func disabledBlockIgnored() {
        let records = makeDebtRecords()
        var block = makeWorkBlock(start: 12.0, end: 17.0)
        block.isEnabled = false

        let result = NapOptimizer.recommend(
            records: records, wakeHour: 6.0,
            contextBlocks: [block],
            weekday: 2
        )

        // Disabled block → should return base recommendation unchanged
        #expect(result != nil)
        if let r = result {
            #expect(r.reason != .contextAdjusted)
        }
    }

    @Test("napConflicts utility correctly detects overlap")
    func napConflictsDetection() {
        // Nap 14:00-15:30, Block 15:00-17:00 → should conflict
        let overlap = ScheduleConflictDetector.circularOverlapMinutes(
            sleepStart: 14.0, sleepEnd: 15.5,
            blockStart: 15.0, blockEnd: 17.0
        )
        #expect(overlap > 5.0)  // 30 min overlap

        // Nap 14:00-14:20, Block 15:00-17:00 → should NOT conflict
        let noOverlap = ScheduleConflictDetector.circularOverlapMinutes(
            sleepStart: 14.0, sleepEnd: 14.333,
            blockStart: 15.0, blockEnd: 17.0
        )
        #expect(noOverlap <= 5.0)
    }
}
