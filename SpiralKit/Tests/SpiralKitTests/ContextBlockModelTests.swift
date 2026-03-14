import Testing
@testable import SpiralKit
import Foundation

@Suite("ContextBlock Model Tests")
struct ContextBlockModelTests {

    // MARK: - ContextSource

    @Test("ContextSource encodes and decodes correctly")
    func contextSourceRoundtrip() throws {
        let manual = ContextSource.manual
        let calendar = ContextSource.calendar

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let manualData = try encoder.encode(manual)
        let calendarData = try encoder.encode(calendar)

        #expect(try decoder.decode(ContextSource.self, from: manualData) == .manual)
        #expect(try decoder.decode(ContextSource.self, from: calendarData) == .calendar)
    }

    // MARK: - effectiveConfidence

    @Test("effectiveConfidence defaults to 1.0 for manual source")
    func confidenceManual() {
        let block = ContextBlock(source: .manual)
        #expect(block.effectiveConfidence == 1.0)
    }

    @Test("effectiveConfidence defaults to 0.85 for calendar source")
    func confidenceCalendar() {
        let block = ContextBlock(source: .calendar)
        #expect(block.effectiveConfidence == 0.85)
    }

    @Test("effectiveConfidence defaults to 1.0 for nil source (legacy)")
    func confidenceLegacy() {
        let block = ContextBlock()
        #expect(block.source == nil)
        #expect(block.confidence == nil)
        #expect(block.effectiveConfidence == 1.0)
    }

    @Test("Explicit confidence overrides source default")
    func confidenceExplicit() {
        let block = ContextBlock(source: .calendar, confidence: 0.5)
        #expect(block.effectiveConfidence == 0.5)
    }

    // MARK: - Backward Compatibility

    @Test("ContextBlock decodes from legacy JSON without source/confidence")
    func legacyDecode() throws {
        // JSON without source or confidence fields
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "type": "work",
            "label": "Morning shift",
            "startHour": 9.0,
            "endHour": 17.0,
            "activeDays": 62,
            "isEnabled": true
        }
        """
        let data = json.data(using: .utf8)!
        let block = try JSONDecoder().decode(ContextBlock.self, from: data)

        #expect(block.type == .work)
        #expect(block.label == "Morning shift")
        #expect(block.source == nil)
        #expect(block.confidence == nil)
        #expect(block.effectiveConfidence == 1.0)
    }

    @Test("ContextBlock with source/confidence roundtrips correctly")
    func fullRoundtrip() throws {
        let block = ContextBlock(
            type: .study,
            label: "Math class",
            startHour: 10.0,
            endHour: 12.0,
            source: .calendar,
            confidence: 0.9
        )

        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContextBlock.self, from: data)

        #expect(decoded.source == .calendar)
        #expect(decoded.confidence == 0.9)
        #expect(decoded.effectiveConfidence == 0.9)
    }

    // MARK: - isHighCognitiveDemand

    @Test("Work, study, commute, focus are high cognitive demand")
    func highCognitiveDemand() {
        #expect(ContextBlockType.work.isHighCognitiveDemand == true)
        #expect(ContextBlockType.study.isHighCognitiveDemand == true)
        #expect(ContextBlockType.commute.isHighCognitiveDemand == true)
        #expect(ContextBlockType.focus.isHighCognitiveDemand == true)
    }

    @Test("Exercise, social, custom are NOT high cognitive demand")
    func lowCognitiveDemand() {
        #expect(ContextBlockType.exercise.isHighCognitiveDemand == false)
        #expect(ContextBlockType.social.isHighCognitiveDemand == false)
        #expect(ContextBlockType.custom.isHighCognitiveDemand == false)
    }

    // MARK: - BufferSeverity in ScheduleConflict

    @Test("BufferSeverity encodes and decodes correctly")
    func bufferSeverityRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let alertData = try encoder.encode(BufferSeverity.alert)
        let highRiskData = try encoder.encode(BufferSeverity.highRisk)

        #expect(try decoder.decode(BufferSeverity.self, from: alertData) == .alert)
        #expect(try decoder.decode(BufferSeverity.self, from: highRiskData) == .highRisk)
    }

    @Test("ScheduleConflict decodes from legacy JSON without bufferSeverity")
    func conflictLegacyDecode() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000002",
            "type": "sleepTooCloseToBlockStart",
            "blockID": "00000000-0000-0000-0000-000000000003",
            "blockType": "work",
            "blockLabel": "Office",
            "day": 3,
            "overlapMinutes": 30.0,
            "sleepEndHour": 7.5,
            "blockStartHour": 8.0
        }
        """
        let data = json.data(using: .utf8)!
        let conflict = try JSONDecoder().decode(ScheduleConflict.self, from: data)

        #expect(conflict.type == .sleepTooCloseToBlockStart)
        #expect(conflict.bufferSeverity == nil)
    }

    // MARK: - Two-Tier Buffer Detection

    @Test("Buffer < 60 min with work block → alert severity")
    func bufferAlert() {
        let records = [makeRecord(bedtime: 0.0, wakeup: 7.25)] // wake 07:15
        let blocks = [makeWorkBlock(start: 8.0, end: 16.0)]    // work at 08:00
        // Gap: 45 min → < 60 min → alert

        let conflicts = ScheduleConflictDetector.detect(
            records: records, blocks: blocks, bufferMinutes: 60.0
        )

        let buffer = conflicts.first { $0.type == .sleepTooCloseToBlockStart }
        #expect(buffer != nil)
        #expect(buffer?.bufferSeverity == .alert)
    }

    @Test("Buffer 60-90 min with high-demand block → highRisk severity")
    func bufferHighRisk() {
        let records = [makeRecord(bedtime: 23.0, wakeup: 6.75)] // wake 06:45
        let blocks = [makeWorkBlock(start: 8.0, end: 16.0)]     // work at 08:00
        // Gap: 75 min → > 60 but < 90 + work (high demand) → highRisk

        let conflicts = ScheduleConflictDetector.detect(
            records: records, blocks: blocks, bufferMinutes: 60.0
        )

        let buffer = conflicts.first { $0.type == .sleepTooCloseToBlockStart }
        #expect(buffer != nil)
        #expect(buffer?.bufferSeverity == .highRisk)
    }

    @Test("Buffer 60-90 min with social block → no conflict")
    func bufferSocialNoConflict() {
        let records = [makeRecord(bedtime: 23.0, wakeup: 6.75)] // wake 06:45
        let blocks = [makeSocialBlock(start: 8.0, end: 10.0)]   // social at 08:00
        // Gap: 75 min → > 60 + social (not high demand) → no conflict

        let conflicts = ScheduleConflictDetector.detect(
            records: records, blocks: blocks, bufferMinutes: 60.0
        )

        let buffer = conflicts.first { $0.type == .sleepTooCloseToBlockStart }
        #expect(buffer == nil)
    }

    @Test("Sufficient buffer (≥ 90 min) with work block → no conflict")
    func sufficientBuffer() {
        let records = [makeRecord(bedtime: 23.0, wakeup: 6.0)]  // wake 06:00
        let blocks = [makeWorkBlock(start: 8.0, end: 16.0)]     // work at 08:00
        // Gap: 120 min → > 90 → no conflict even for high demand

        let conflicts = ScheduleConflictDetector.detect(
            records: records, blocks: blocks, bufferMinutes: 60.0
        )

        let buffer = conflicts.first { $0.type == .sleepTooCloseToBlockStart }
        #expect(buffer == nil)
    }

    // MARK: - Helpers

    private func makeRecord(bedtime: Double, wakeup: Double) -> SleepRecord {
        SleepRecord(
            day: 0,
            date: Date(),
            isWeekend: false,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: wakeup > bedtime ? wakeup - bedtime : wakeup - bedtime + 24,
            phases: [],
            hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 1.0) },
            cosinor: .empty,
            driftMinutes: 0
        )
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

    private func makeSocialBlock(start: Double, end: Double) -> ContextBlock {
        ContextBlock(
            type: .social,
            label: "Social",
            startHour: start,
            endHour: end,
            activeDays: ContextBlock.everyDay,
            isEnabled: true
        )
    }
}
