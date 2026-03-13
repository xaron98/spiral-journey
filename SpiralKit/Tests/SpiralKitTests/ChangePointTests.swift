import Foundation
import Testing
@testable import SpiralKit

@Suite("ChangePointDetection Tests")
struct ChangePointTests {

    @Test("Constant series has no change points")
    func constantNoChange() {
        let values = Array(repeating: 5.0, count: 20)
        let points = ChangePointDetection.detect(values: values)
        #expect(points.isEmpty)
    }

    @Test("Series with abrupt shift detects one change point")
    func abruptShift() {
        // 10 days at value 2.0, then 10 days at value 8.0
        let values = Array(repeating: 2.0, count: 10) + Array(repeating: 8.0, count: 10)
        let points = ChangePointDetection.detect(values: values)
        #expect(points.count == 1)
        #expect(points[0] == 10, "Expected change at index 10, got \(points)")
    }

    @Test("Too few data points returns empty")
    func tooFewPoints() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        let points = ChangePointDetection.detect(values: values)
        #expect(points.isEmpty)
    }

    @Test("Gradual change may not trigger detection")
    func gradualChange() {
        // Linear ramp — no abrupt shift
        let values = (0..<20).map { Double($0) * 0.1 }
        let points = ChangePointDetection.detect(values: values)
        // May or may not detect — just verify it doesn't crash
        // and returns at most 1 point
        #expect(points.count <= 1)
    }

    @Test("detectInRecords with stable records returns no changes")
    func stableRecords() {
        let records = (0..<14).map { day in
            SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: 23, wakeupHour: 7, sleepDuration: 8,
                phases: [],
                hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
                cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0,
                                       period: 24, r2: 0.8)
            )
        }
        let changes = ChangePointDetection.detectInRecords(records)
        #expect(changes.isEmpty)
    }

    @Test("detectInRecords detects bedtime shift")
    func bedtimeShift() {
        var records: [SleepRecord] = []
        for day in 0..<20 {
            let bedtime: Double = day < 10 ? 23.0 : 2.0  // 3h shift at day 10
            records.append(SleepRecord(
                day: day, date: Date(), isWeekend: false,
                bedtimeHour: bedtime, wakeupHour: 7, sleepDuration: 8,
                phases: [],
                hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
                cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15.0,
                                       period: 24, r2: 0.8)
            ))
        }
        let changes = ChangePointDetection.detectInRecords(records)
        let bedtimeChanges = changes.filter { $0.metric == "bedtime" }
        #expect(!bedtimeChanges.isEmpty, "Should detect bedtime shift")
        if let first = bedtimeChanges.first {
            #expect(first.index == 10, "Expected change at day 10, got \(first.index)")
        }
    }

    @Test("Too few records returns empty")
    func tooFewRecords() {
        let records = (0..<3).map { day in
            SleepRecord(
                day: day, date: Date(), isWeekend: false,
                bedtimeHour: 23, wakeupHour: 7, sleepDuration: 8,
                phases: [],
                hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
                cosinor: .empty
            )
        }
        let changes = ChangePointDetection.detectInRecords(records)
        #expect(changes.isEmpty)
    }
}
