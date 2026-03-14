import Testing
@testable import SpiralKit
import Foundation

@Suite("SleepinessRisk Tests")
struct SleepinessRiskTests {

    // MARK: - Helpers

    private func makeRecord(day: Int, bedtime: Double, wakeup: Double, date: Date? = nil) -> SleepRecord {
        let cal = Calendar.current
        let d = date ?? (cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: Date())) ?? Date())

        // Build hourlyActivity: asleep during bed→wake, awake otherwise
        let hourly: [HourlyActivity] = (0..<24).map { h in
            let hour = Double(h)
            let asleep: Bool
            if bedtime < wakeup {
                asleep = hour >= bedtime && hour < wakeup
            } else {
                // Overnight: e.g. 23:00-07:00
                asleep = hour >= bedtime || hour < wakeup
            }
            return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.85)
        }

        return SleepRecord(
            day: day,
            date: d,
            isWeekend: false,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: wakeup > bedtime ? wakeup - bedtime : wakeup - bedtime + 24,
            phases: [],
            hourlyActivity: hourly,
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

    // MARK: - Tests

    @Test("No context blocks → empty results")
    func noBlocks() {
        let records = [makeRecord(day: 0, bedtime: 23.0, wakeup: 7.0)]
        let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: [])
        #expect(risks.isEmpty)
    }

    @Test("No records → empty results")
    func noRecords() {
        let blocks = [makeWorkBlock(start: 9.0, end: 17.0)]
        let risks = SleepinessRiskEngine.evaluate(records: [], contextBlocks: blocks)
        #expect(risks.isEmpty)
    }

    @Test("Disabled block → ignored")
    func disabledBlock() {
        let records = [makeRecord(day: 0, bedtime: 23.0, wakeup: 7.0)]
        var block = makeWorkBlock(start: 9.0, end: 17.0)
        block.isEnabled = false

        let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: [block])
        #expect(risks.isEmpty)
    }

    @Test("Day worker with normal sleep → low risk")
    func dayWorkerLowRisk() {
        // Good sleep 23:00-07:00, work 09:00-17:00
        let records = (0..<5).map { day in
            makeRecord(day: day, bedtime: 23.0, wakeup: 7.0)
        }
        let blocks = [makeWorkBlock(start: 9.0, end: 17.0)]

        let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: blocks)

        // Should have 1 result for the work block
        #expect(risks.count == 1)
        if let risk = risks.first {
            #expect(risk.blockLabel == "Work")
            // With 8h sleep and work after 2h buffer, S should be relatively low
            #expect(risk.riskLevel == .low || risk.riskLevel == .moderate)
        }
    }

    @Test("Night shift worker with short daytime sleep → elevated risk")
    func nightShiftElevatedRisk() {
        // Only 4-5h daytime sleep (08:00-13:00), work 22:00-06:00
        let records = (0..<5).map { day in
            makeRecord(day: day, bedtime: 8.0, wakeup: 13.0)
        }
        let blocks = [makeWorkBlock(start: 22.0, end: 6.0)]

        let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: blocks)

        // Should detect some level of risk during night hours
        #expect(!risks.isEmpty)
        if let risk = risks.first {
            // With 5h sleep and overnight work, S should build up
            #expect(risk.riskLevel == .moderate || risk.riskLevel == .high)
        }
    }

    @Test("Results are sorted by risk level descending")
    func sortedByRisk() {
        let records = (0..<3).map { day in
            makeRecord(day: day, bedtime: 8.0, wakeup: 12.0) // Only 4h sleep
        }

        // Two blocks: one overnight (likely higher risk), one daytime
        let blocks = [
            makeWorkBlock(start: 22.0, end: 6.0),
            ContextBlock(type: .social, label: "Social", startHour: 14.0, endHour: 16.0,
                        activeDays: ContextBlock.everyDay, isEnabled: true)
        ]

        let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: blocks)

        // Should be sorted: highest risk first
        for i in 0..<(risks.count - 1) {
            #expect(risks[i].riskLevel >= risks[i + 1].riskLevel)
        }
    }

    @Test("Multiple records build sleep pressure correctly")
    func multipleRecordsPressure() {
        // 3 days of 5h sleep should build more pressure than 3 days of 8h
        let shortSleep = (0..<3).map { makeRecord(day: $0, bedtime: 2.0, wakeup: 7.0) }
        let goodSleep = (0..<3).map { makeRecord(day: $0, bedtime: 23.0, wakeup: 7.0) }
        let blocks = [makeWorkBlock(start: 9.0, end: 17.0)]

        let shortRisks = SleepinessRiskEngine.evaluate(records: shortSleep, contextBlocks: blocks)
        let goodRisks = SleepinessRiskEngine.evaluate(records: goodSleep, contextBlocks: blocks)

        // Short sleep should produce higher meanS
        if let sr = shortRisks.first, let gr = goodRisks.first {
            #expect(sr.meanS >= gr.meanS)
        }
    }
}
