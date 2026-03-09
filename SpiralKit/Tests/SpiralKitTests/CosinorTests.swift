import Testing
import Foundation
@testable import SpiralKit

@Suite("CosinorAnalysis")
struct CosinorTests {

    /// Build synthetic hourly activity: low during sleep, high during wake.
    /// Bedtime ~23h, wakeup ~7h → activity peak around 14-15h.
    private func makeSleepActivity(bedtime: Double = 23.0, wakeup: Double = 7.0) -> [HourlyActivity] {
        (0..<24).map { h in
            let hour = Double(h)
            let isSleeping: Bool
            if bedtime > wakeup {
                isSleeping = hour >= bedtime || hour < wakeup
            } else {
                isSleeping = hour >= bedtime && hour < wakeup
            }
            return HourlyActivity(hour: h, activity: isSleeping ? 0.05 : 0.75)
        }
    }

    @Test("Cosinor fit returns plausible results for typical sleep data")
    func testFitTypicalSleep() {
        let data = makeSleepActivity()
        let result = CosinorAnalysis.fit(data)

        #expect(result.mesor > 0 && result.mesor < 1)
        #expect(result.amplitude > 0)
        #expect(result.acrophase >= 0 && result.acrophase < 24)
        #expect(result.r2 >= 0 && result.r2 <= 1)
        // Activity peak should be around midday for sleep 23-07
        #expect(result.acrophase > 10 && result.acrophase < 20,
                "Acrophase \(result.acrophase) should be roughly midday for 23-07 sleep")
    }

    @Test("Cosinor fit with fewer than 3 data points returns empty result")
    func testFitTooFewPoints() {
        let result = CosinorAnalysis.fit([])
        #expect(result.r2 == 0)
        #expect(result.amplitude == 0.3)   // default from CosinorResult.empty

        let two = [HourlyActivity(hour: 0, activity: 0.5), HourlyActivity(hour: 12, activity: 0.5)]
        let r2 = CosinorAnalysis.fit(two)
        #expect(r2.r2 == 0)
    }

    @Test("Acrophase is in [0, 24)")
    func testAcrophaseBounds() {
        for _ in 0..<10 {
            let data = (0..<24).map { HourlyActivity(hour: $0, activity: Double.random(in: 0...1)) }
            let result = CosinorAnalysis.fit(data)
            #expect(result.acrophase >= 0 && result.acrophase < 24)
        }
    }

    @Test("R² is in [0, 1]")
    func testR2Bounds() {
        let data = makeSleepActivity()
        let result = CosinorAnalysis.fit(data)
        #expect(result.r2 >= 0 && result.r2 <= 1)
    }

    @Test("Rhythm stability is 1 for identical acrophases")
    func testRhythmStabilityPerfect() {
        let results = (0..<7).map { _ in
            CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.8)
        }
        let stability = CosinorAnalysis.rhythmStability(results)
        #expect(abs(stability - 1.0) < 0.001)
    }

    @Test("Sliding cosinor returns correct number of windows")
    func testSlidingCosinorCount() {
        let records = (0..<14).map { day -> SleepRecord in
            let activity = makeSleepActivity()
            return SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: 23, wakeupHour: 7, sleepDuration: 8,
                phases: [], hourlyActivity: activity,
                cosinor: CosinorAnalysis.fit(activity)
            )
        }
        let sliding = CosinorAnalysis.slidingFit(records, windowDays: 7)
        // For 14 days and window 7: indices 0..7 → 8 windows
        #expect(sliding.count == 8)
    }
}
