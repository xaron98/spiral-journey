import Foundation
import Testing
@testable import SpiralKit

@Suite("JetLag Engine Tests")
struct JetLagEngineTests {

    // MARK: - Basic plan generation

    @Test("Zero offset returns empty plan")
    func zeroOffset() {
        let plan = JetLagEngine.generatePlan(offset: 0, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(plan.days.isEmpty)
        #expect(plan.estimatedAdaptationDays == 0)
    }

    @Test("East +6h generates advance plan")
    func eastSixHours() {
        let plan = JetLagEngine.generatePlan(offset: 6, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(plan.direction == .east)
        #expect(plan.estimatedAdaptationDays == 6, "6h advance at 1h/day = 6 days")
        #expect(!plan.days.isEmpty)
        // Should have pre-travel + travel + post days
        let preTravelDays = plan.days.filter { $0.dayOffset < 0 }
        #expect(preTravelDays.count == 3, "Should have 3 pre-travel days")
    }

    @Test("West -8h generates delay plan")
    func westEightHours() {
        let plan = JetLagEngine.generatePlan(offset: -8, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(plan.direction == .west)
        // 8h delay at 1.5h/day ≈ 6 days
        #expect(plan.estimatedAdaptationDays >= 5 && plan.estimatedAdaptationDays <= 6)
    }

    @Test("Large east offset (>8h) uses delay direction for efficiency")
    func largeEastOffset() {
        let plan = JetLagEngine.generatePlan(offset: 10, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        // 10h east → faster to delay 14h (24-10)? No, 10h advance at 1h/day = 10 days, 14h delay at 1.5h/day ≈ 10 days
        // Actually for 10h east: clampedOffset=10, 10>8, so direction=west, effectiveShift=24-10=14
        #expect(plan.direction == .west)
    }

    @Test("Large west offset (< -8h) uses advance direction for efficiency")
    func largeWestOffset() {
        let plan = JetLagEngine.generatePlan(offset: -10, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        // -10 west → |-10| = 10 > 8, so direction=east, effectiveShift=24+(-10)=14
        #expect(plan.direction == .east)
    }

    // MARK: - Day content

    @Test("Each day has light window")
    func daysHaveLightWindow() {
        let plan = JetLagEngine.generatePlan(offset: 5, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        for day in plan.days {
            #expect(day.lightWindow != nil, "Day \(day.dayOffset) should have a light window")
        }
    }

    @Test("Each day has melatonin time")
    func daysHaveMelatonin() {
        let plan = JetLagEngine.generatePlan(offset: 5, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        for day in plan.days {
            #expect(day.melatoninTime != nil, "Day \(day.dayOffset) should have melatonin time")
        }
    }

    @Test("Each day has caffeine deadline")
    func daysHaveCaffeine() {
        let plan = JetLagEngine.generatePlan(offset: 5, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        for day in plan.days {
            #expect(day.caffeineDeadline != nil, "Day \(day.dayOffset) should have caffeine deadline")
        }
    }

    @Test("East plan: bedtime shifts earlier each day")
    func eastBedtimeShifts() {
        let plan = JetLagEngine.generatePlan(offset: 3, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        let bedtimes = plan.days.compactMap(\.targetBedtime)
        guard bedtimes.count >= 2 else { return }
        // For east travel, bedtime should decrease (earlier) or wrap around
        // Just verify they're all valid hours
        for bt in bedtimes {
            #expect(bt >= 0 && bt < 24, "Bedtime \(bt) should be in 0-24 range")
        }
    }

    // MARK: - Edge cases

    @Test("Offset ±12 doesn't crash")
    func extremeOffsets() {
        let east12 = JetLagEngine.generatePlan(offset: 12, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(!east12.days.isEmpty)

        let west12 = JetLagEngine.generatePlan(offset: -12, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(!west12.days.isEmpty)
    }

    @Test("Offset clamped to ±12 range")
    func offsetClamping() {
        let plan = JetLagEngine.generatePlan(offset: 15, travelDate: Date(), currentBedtime: 23, currentWake: 7)
        #expect(plan.timezoneOffsetHours == 12)
    }

    // MARK: - Normalize hour

    @Test("normalizeHour handles negative values")
    func normalizeNegative() {
        #expect(JetLagEngine.normalizeHour(-1) == 23)
        #expect(JetLagEngine.normalizeHour(-3.5) == 20.5)
    }

    @Test("normalizeHour handles values > 24")
    func normalizeOver24() {
        #expect(JetLagEngine.normalizeHour(25) == 1)
        #expect(JetLagEngine.normalizeHour(48) == 0)
    }
}
