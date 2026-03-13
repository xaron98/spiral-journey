import Foundation
import Testing
@testable import SpiralKit

@Suite("Autocorrelation Tests")
struct AutocorrelationTests {

    // MARK: - Helpers

    private func makeRecords(count: Int, activity: (Int, Int) -> Double) -> [SleepRecord] {
        (0..<count).map { day in
            SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: 23, wakeupHour: 7, sleepDuration: 8,
                phases: [],
                hourlyActivity: (0..<24).map { h in
                    HourlyActivity(hour: h, activity: activity(day, h))
                },
                cosinor: .empty
            )
        }
    }

    // MARK: - Legacy method regression

    @Test("Legacy compute returns results for 7 lags × 24 hours")
    func legacyShape() {
        let records = makeRecords(count: 14) { _, h in h < 7 || h >= 23 ? 0.05 : 0.9 }
        let result = Autocorrelation.compute(records, maxLag: 7)
        #expect(result.count == 24 * 7)
    }

    @Test("Legacy compute with identical days gives high correlation")
    func legacyIdenticalDays() {
        let records = makeRecords(count: 10) { _, h in h < 7 || h >= 23 ? 0.05 : 0.9 }
        let result = Autocorrelation.compute(records, maxLag: 3)
        for point in result {
            #expect(point.correlation > 0.99, "Expected high correlation for identical days, got \(point.correlation) at hour=\(point.hour) lag=\(point.lag)")
        }
    }

    // MARK: - Extended autocorrelation

    @Test("Extended autocorrelation returns results for default lags × 24 hours")
    func extendedShape() {
        let records = makeRecords(count: 35) { _, h in h < 7 || h >= 23 ? 0.05 : 0.9 }
        let result = Autocorrelation.computeExtended(records, lags: [1, 2, 7, 14, 28], permutations: 50, seed: 42)
        #expect(result.count == 24 * 5)
    }

    @Test("Weekly periodic pattern shows high correlation at lag 7")
    func extendedWeeklyPattern() {
        // Activity varies linearly with day-of-week, creating a 7-day cycle.
        // Lag 7 should show high correlation, lag 1 should be lower.
        let records = makeRecords(count: 35) { day, h in
            let dayOfWeek = Double(day % 7) / 7.0  // 0..0.86, repeats weekly
            let hourFactor = Double(h) / 24.0
            return dayOfWeek * 0.5 + hourFactor * 0.3 + 0.1
        }
        let lag7 = Autocorrelation.computeExtended(records, lags: [7], permutations: 50, seed: 42)
        let lag1 = Autocorrelation.computeExtended(records, lags: [1], permutations: 50, seed: 42)
        let meanCorr7 = lag7.map(\.correlation).reduce(0, +) / Double(lag7.count)
        let meanCorr1 = lag1.map(\.correlation).reduce(0, +) / Double(lag1.count)
        #expect(meanCorr7 > meanCorr1, "Lag 7 should show higher correlation than lag 1 for weekly pattern")
        #expect(meanCorr7 > 0.5, "Weekly pattern should have strong correlation at lag 7, got \(meanCorr7)")
    }

    @Test("Insufficient data for lag returns zero correlation and non-significant")
    func extendedInsufficientData() {
        let records = makeRecords(count: 5) { _, h in h < 7 || h >= 23 ? 0.05 : 0.9 }
        let result = Autocorrelation.computeExtended(records, lags: [14], permutations: 50, seed: 42)
        for point in result {
            #expect(point.correlation == 0)
            #expect(point.pValue == 1.0)
            #expect(!point.isSignificant)
        }
    }

    @Test("p-values are in [0, 1]")
    func extendedPValueRange() {
        let records = makeRecords(count: 20) { _, h in h < 7 || h >= 23 ? 0.05 : 0.9 }
        let result = Autocorrelation.computeExtended(records, lags: [1, 7], permutations: 50, seed: 42)
        for point in result {
            #expect(point.pValue >= 0 && point.pValue <= 1,
                    "p-value out of range: \(point.pValue)")
        }
    }

    @Test("Seeded computation is deterministic")
    func extendedDeterministic() {
        let records = makeRecords(count: 20) { day, h in
            let base: Double = (h < 7 || h >= 23) ? 0.05 : 0.9
            return base + Double(day % 3) * 0.05
        }
        let r1 = Autocorrelation.computeExtended(records, lags: [1, 7], permutations: 50, seed: 123)
        let r2 = Autocorrelation.computeExtended(records, lags: [1, 7], permutations: 50, seed: 123)
        #expect(r1.count == r2.count)
        for i in 0..<r1.count {
            #expect(r1[i].pValue == r2[i].pValue, "Results should be identical with same seed")
        }
    }

    @Test("SignificantCorrelation fields are populated correctly")
    func extendedFieldsPopulated() {
        let records = makeRecords(count: 20) { day, h in
            Double(h) / 24.0 + Double(day % 4) * 0.1
        }
        let result = Autocorrelation.computeExtended(records, lags: [1], permutations: 30, seed: 99)
        for point in result {
            #expect(point.hour >= 0 && point.hour < 24)
            #expect(point.lag == 1)
            #expect(point.correlation >= -1 && point.correlation <= 1)
            #expect(point.isSignificant == (point.pValue < 0.05))
        }
    }
}
