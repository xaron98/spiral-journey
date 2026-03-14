import Testing
@testable import SpiralKit
import Foundation

@Suite("ConflictTrend Tests")
struct ConflictTrendTests {

    // MARK: - Helpers

    /// Create a snapshot for a given day offset with a specified conflict count.
    private func makeSnapshot(dayOffset: Int, totalConflicts: Int, overlaps: Int = 0, bufferAlerts: Int = 0, daytime: Int = 0, meanBuffer: Double? = nil) -> ConflictSnapshot {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())!
        return ConflictSnapshot(
            date: date,
            totalConflicts: totalConflicts,
            overlapCount: overlaps,
            bufferAlertCount: bufferAlerts,
            daytimeSleepCount: daytime,
            meanBufferMinutes: meanBuffer
        )
    }

    // MARK: - Tests

    @Test("Fewer than 7 snapshots → nil")
    func insufficientData() {
        let snapshots = (0..<5).map { makeSnapshot(dayOffset: $0, totalConflicts: 2) }
        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result == nil)
    }

    @Test("Exactly 7 snapshots (one week only) → stable (no previous to compare)")
    func oneWeekOnly() {
        let snapshots = (0..<7).map { makeSnapshot(dayOffset: $0, totalConflicts: 3) }
        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .stable)
            #expect(r.currentWeekConflicts == 21)
        }
    }

    @Test("14 decreasing snapshots → improving")
    func decreasingIsImproving() {
        // Week 1 (days 0-6): 5 conflicts each = 35 total
        // Week 2 (days 7-13): 1 conflict each = 7 total
        var snapshots: [ConflictSnapshot] = []
        for i in 0..<7 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 5))
        }
        for i in 7..<14 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 1))
        }
        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .improving)
            #expect(r.currentWeekConflicts == 7)
            #expect(r.previousWeekConflicts == 35)
            #expect(r.weekOverWeekDelta == -28)
        }
    }

    @Test("14 increasing snapshots → worsening")
    func increasingIsWorsening() {
        // Week 1: 1 conflict each = 7 total
        // Week 2: 5 conflicts each = 35 total
        var snapshots: [ConflictSnapshot] = []
        for i in 0..<7 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 1))
        }
        for i in 7..<14 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 5))
        }
        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .worsening)
            #expect(r.weekOverWeekDelta == 28)
        }
    }

    @Test("Constant snapshots → stable")
    func constantIsStable() {
        let snapshots = (0..<14).map { makeSnapshot(dayOffset: $0, totalConflicts: 3) }
        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .stable)
            #expect(r.weekOverWeekDelta == 0)
        }
    }

    @Test("Small delta within threshold → stable")
    func smallDeltaIsStable() {
        // Week 1: 3 conflicts each = 21, Week 2: 3 then 3 then 3 then 3 then 3 then 3 then 4 = 22
        // Delta = 1, which is within stability threshold
        var snapshots: [ConflictSnapshot] = []
        for i in 0..<7 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 3))
        }
        for i in 7..<13 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 3))
        }
        snapshots.append(makeSnapshot(dayOffset: 13, totalConflicts: 4))

        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .stable)
        }
    }

    @Test("Mean buffer is computed for current and previous weeks")
    func meanBufferComputed() {
        var snapshots: [ConflictSnapshot] = []
        // Week 1: buffer 30 min each
        for i in 0..<7 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 2, meanBuffer: 30.0))
        }
        // Week 2: buffer 50 min each
        for i in 7..<14 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 1, meanBuffer: 50.0))
        }

        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.currentMeanBuffer != nil)
            #expect(r.previousMeanBuffer != nil)
            // Current week buffer ≈ 50, previous ≈ 30
            if let cur = r.currentMeanBuffer, let prev = r.previousMeanBuffer {
                #expect(cur > prev)
            }
        }
    }

    @Test("ConflictSnapshot.from() counts conflict types correctly")
    func snapshotFromConflicts() {
        let conflicts: [ScheduleConflict] = [
            ScheduleConflict(type: .sleepOverlapsBlock, blockID: UUID(), blockType: .work,
                           blockLabel: "Work", day: 0, overlapMinutes: 60,
                           sleepEndHour: 7.0, blockStartHour: 6.5),
            ScheduleConflict(type: .sleepOverlapsBlock, blockID: UUID(), blockType: .work,
                           blockLabel: "Work", day: 1, overlapMinutes: 30,
                           sleepEndHour: 7.0, blockStartHour: 6.5),
            ScheduleConflict(type: .sleepTooCloseToBlockStart, blockID: UUID(), blockType: .study,
                           blockLabel: "Study", day: 0, overlapMinutes: 20,
                           sleepEndHour: 8.5, blockStartHour: 9.0),
            ScheduleConflict(type: .daytimeSleepConsumesWindow, blockID: UUID(), blockType: .work,
                           blockLabel: "Work", day: 2, overlapMinutes: 90,
                           sleepEndHour: 14.0, blockStartHour: 9.0)
        ]

        let snapshot = ConflictSnapshot.from(conflicts: conflicts)
        #expect(snapshot.totalConflicts == 4)
        #expect(snapshot.overlapCount == 2)
        #expect(snapshot.bufferAlertCount == 1)
        #expect(snapshot.daytimeSleepCount == 1)
        #expect(snapshot.meanBufferMinutes != nil)
    }

    @Test("ConflictSnapshot.from() with no conflicts → all zeros")
    func snapshotFromEmpty() {
        let snapshot = ConflictSnapshot.from(conflicts: [])
        #expect(snapshot.totalConflicts == 0)
        #expect(snapshot.overlapCount == 0)
        #expect(snapshot.bufferAlertCount == 0)
        #expect(snapshot.daytimeSleepCount == 0)
        #expect(snapshot.meanBufferMinutes == nil)
    }

    @Test("Trim keeps most recent 90 days and deduplicates by date")
    func trimDeduplicates() {
        // Create 100 snapshots for consecutive days
        var snapshots: [ConflictSnapshot] = []
        for i in 0..<100 {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: i))
        }
        // Add a duplicate for day 50
        snapshots.append(makeSnapshot(dayOffset: 50, totalConflicts: 999))

        let trimmed = ConflictTrendEngine.trimmed(snapshots, maxDays: 90)
        #expect(trimmed.count <= 90)
        // Should be sorted by date
        for i in 0..<(trimmed.count - 1) {
            #expect(trimmed[i].date <= trimmed[i + 1].date)
        }
    }

    @Test("Unsorted input produces correct analysis")
    func unsortedInput() {
        // Create snapshots in reverse order
        var snapshots: [ConflictSnapshot] = []
        // Current week (most recent): 1 conflict each
        for i in (7..<14).reversed() {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 1))
        }
        // Previous week: 5 conflicts each
        for i in (0..<7).reversed() {
            snapshots.append(makeSnapshot(dayOffset: i, totalConflicts: 5))
        }

        let result = ConflictTrendEngine.analyze(snapshots: snapshots)
        #expect(result != nil)
        if let r = result {
            #expect(r.direction == .improving)
        }
    }
}
