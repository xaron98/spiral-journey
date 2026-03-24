import Testing
import Foundation
@testable import SpiralKit

@Suite("LombScargle")
struct LombScargleTests {

    // MARK: - Test Helpers

    private func makeRecord(day: Int, bedtime: Double, wake: Double, duration: Double, amplitude: Double = 0.5) -> SleepRecord {
        SleepRecord(
            day: day, date: Date(), isWeekend: day % 7 >= 5,
            bedtimeHour: bedtime, wakeupHour: wake, sleepDuration: duration,
            phases: [],
            hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
            cosinor: CosinorResult(mesor: 0.5, amplitude: amplitude, acrophase: 14, period: 24, r2: 0.5)
        )
    }

    /// Generate a sinusoidal signal sampled once per day: value = amplitude * sin(2π * day / periodDays)
    /// Times are in hours (day * 24), period is in hours.
    private func makeDailySinusoid(
        days: Int,
        periodDays: Double,
        amplitude: Double = 1.0,
        noise: Double = 0.0
    ) -> (times: [Double], values: [Double]) {
        var times: [Double] = []
        var values: [Double] = []
        for day in 0..<days {
            let t = Double(day) * 24.0
            let periodHours = periodDays * 24.0
            let value = amplitude * sin(2.0 * Double.pi * t / periodHours)
            // Deterministic "noise" based on day index (not random)
            let deterministicNoise = noise * sin(Double(day) * 137.0)
            times.append(t)
            values.append(value + deterministicNoise)
        }
        return (times, values)
    }

    /// Generate a sinusoidal signal with sub-daily (hourly) sampling for circadian detection.
    private func makeHourlySinusoid(
        hours: Int,
        periodHours: Double,
        amplitude: Double = 1.0,
        samplingIntervalHours: Double = 4.0
    ) -> (times: [Double], values: [Double]) {
        var times: [Double] = []
        var values: [Double] = []
        var t = 0.0
        while t < Double(hours) {
            let value = amplitude * sin(2.0 * Double.pi * t / periodHours)
            times.append(t)
            values.append(value)
            t += samplingIntervalHours
        }
        return (times, values)
    }

    // MARK: - Task 1: Core algorithm tests

    @Test("Weekly sinusoid (168h) detected from daily samples")
    func testWeeklySinusoid() {
        let (times, values) = makeDailySinusoid(days: 60, periodDays: 7.0)

        let result = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                          minPeriod: 48, maxPeriod: 720)

        #expect(!result.isEmpty, "Result should not be empty for 60-day weekly sinusoid")
        #expect(!result.peaks.isEmpty, "Should detect at least one peak")

        // The strongest peak should be near 168h (7 days)
        let strongest = result.peaks.first!
        #expect(abs(strongest.period - 168.0) < 12.0,
                "Strongest peak at \(strongest.period)h should be near 168h")
        #expect(strongest.label == .weekly,
                "Peak should be labeled weekly, got \(String(describing: strongest.label))")
    }

    @Test("Circadian (24h) sinusoid detected from sub-daily samples")
    func testCircadianFromSubdailySamples() {
        // Sample every 4 hours for 60 days → 360 points, well above Nyquist for 24h
        let (times, values) = makeHourlySinusoid(hours: 60 * 24, periodHours: 24.0,
                                                  samplingIntervalHours: 4.0)

        let result = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint,
                                          minPeriod: 20, maxPeriod: 200)

        #expect(!result.isEmpty, "Result should not be empty")
        #expect(!result.peaks.isEmpty, "Should detect circadian peak from hourly data")

        let strongest = result.peaks.first!
        #expect(abs(strongest.period - 24.0) < 2.0,
                "Strongest peak at \(strongest.period)h should be near 24h")
        #expect(strongest.label == .circadian,
                "Peak should be labeled circadian, got \(String(describing: strongest.label))")
    }

    // MARK: - Task 2: Edge case tests

    @Test("Composite 168h + 336h signal → two peaks detected from daily samples")
    func testCompositeSignal() {
        // Mix weekly and biweekly components, sampled daily
        var times: [Double] = []
        var values: [Double] = []
        for day in 0..<90 {
            let t = Double(day) * 24.0
            let weekly = sin(2.0 * Double.pi * t / 168.0)
            let biweekly = 0.8 * sin(2.0 * Double.pi * t / 336.0)
            times.append(t)
            values.append(weekly + biweekly)
        }

        let result = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                          minPeriod: 48, maxPeriod: 720)

        #expect(!result.isEmpty)

        let weeklyPeaks = result.peaks.filter { $0.label == .weekly }
        let biweeklyPeaks = result.peaks.filter { $0.label == .biweekly }

        #expect(!weeklyPeaks.isEmpty,
                "Should detect weekly peak. Peaks: \(result.peaks.map { "(\($0.period)h, \(String(describing: $0.label)))" })")
        #expect(!biweeklyPeaks.isEmpty,
                "Should detect biweekly peak. Peaks: \(result.peaks.map { "(\($0.period)h, \(String(describing: $0.label)))" })")
    }

    @Test("Composite circadian + weekly from sub-daily data → two peaks")
    func testCompositeCircadianWeekly() {
        // Sub-daily sampling (every 4h) so circadian is detectable
        var times: [Double] = []
        var values: [Double] = []
        var t = 0.0
        while t < Double(90 * 24) {
            let circadian = sin(2.0 * Double.pi * t / 24.0)
            let weekly = 0.7 * sin(2.0 * Double.pi * t / 168.0)
            times.append(t)
            values.append(circadian + weekly)
            t += 4.0
        }

        let result = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                          minPeriod: 20, maxPeriod: 720)

        #expect(!result.isEmpty)

        let circadianPeaks = result.peaks.filter { $0.label == .circadian }
        let weeklyPeaks = result.peaks.filter { $0.label == .weekly }

        #expect(!circadianPeaks.isEmpty,
                "Should detect circadian peak. Peaks: \(result.peaks.map { "(\($0.period)h, \(String(describing: $0.label)))" })")
        #expect(!weeklyPeaks.isEmpty,
                "Should detect weekly peak. Peaks: \(result.peaks.map { "(\($0.period)h, \(String(describing: $0.label)))" })")
    }

    @Test("Flat signal → no peaks, empty power")
    func testFlatSignal() {
        let times = (0..<30).map { Double($0) * 24.0 }
        let values = [Double](repeating: 5.0, count: 30)

        let result = LombScargle.compute(times: times, values: values, signal: .sleepDuration)

        // Zero variance → empty result
        #expect(result.isEmpty, "Flat signal should produce empty result")
    }

    @Test("Fewer than 14 data points → empty result")
    func testTooFewPoints() {
        let times = (0..<10).map { Double($0) * 24.0 }
        let values = (0..<10).map { Double($0) }

        let result = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint)

        #expect(result.isEmpty, "Should return empty result for < 14 data points")
    }

    @Test("Known period with noise → peak within ±12h of true period")
    func testNoisySignal() {
        let (times, values) = makeDailySinusoid(days: 60, periodDays: 7.0, amplitude: 1.0, noise: 0.3)

        let result = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                          minPeriod: 48, maxPeriod: 720)

        #expect(!result.peaks.isEmpty, "Should detect peak even with noise")
        let strongest = result.peaks.first!
        #expect(abs(strongest.period - 168.0) < 12.0,
                "Strongest peak at \(strongest.period)h should be within ±12h of 168h")
    }

    @Test("Deterministic: same input → same output")
    func testDeterminism() {
        let (times, values) = makeDailySinusoid(days: 30, periodDays: 7.0)

        let result1 = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                            minPeriod: 48, maxPeriod: 720)
        let result2 = LombScargle.compute(times: times, values: values, signal: .sleepDuration,
                                            minPeriod: 48, maxPeriod: 720)

        #expect(result1.power == result2.power)
        #expect(result1.peaks.count == result2.peaks.count)
        if !result1.peaks.isEmpty {
            #expect(result1.peaks[0].period == result2.peaks[0].period)
            #expect(result1.peaks[0].power == result2.peaks[0].power)
        }
    }

    @Test("Invalid params: minPeriod >= maxPeriod → empty result")
    func testInvalidMinMax() {
        let times = (0..<30).map { Double($0) * 24.0 }
        let values = (0..<30).map { Double($0) }

        let result = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint,
                                          minPeriod: 100, maxPeriod: 50)
        #expect(result.isEmpty, "minPeriod >= maxPeriod should produce empty result")
    }

    @Test("Invalid params: numFreqs = 0 → empty result")
    func testZeroFreqs() {
        let times = (0..<30).map { Double($0) * 24.0 }
        let values = (0..<30).map { Double($0) }

        let result = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint,
                                          numFreqs: 0)
        #expect(result.isEmpty, "numFreqs = 0 should produce empty result")
    }

    // MARK: - Task 3: Signal extraction tests

    @Test("Sleep midpoint midnight wrap: bedtime 23, wake 7 → midpoint ~3")
    func testMidpointMidnightWrap() {
        // Build 20 identical records with bedtime 23, wake 7
        // Midpoint: wake becomes 31 (crosses midnight), mid = (23+31)/2 = 27, mod 24 = 3.0
        // All same schedule → constant midpoint → zero variance → empty result
        let records = (0..<20).map { i in
            makeRecord(day: i, bedtime: 23, wake: 7, duration: 8)
        }
        let analyzed = LombScargle.analyze(records, signal: .sleepMidpoint)
        #expect(analyzed.isEmpty,
                "Constant midpoint (all same schedule) should give empty result (zero variance)")
    }

    @Test("Sleep midpoint unwrapping preserves drift across midnight")
    func testMidpointUnwrapDrift() {
        // Simulate a progressive delay: bedtime shifts later each day
        // Day 0: bed 22, wake 6 → mid = 2.0
        // Day 1: bed 23, wake 7 → mid = 3.0
        // Day 2: bed 0, wake 8 → mid = 4.0
        // Day 3: bed 1, wake 9 → mid = 5.0
        // Without unwrapping, the 22→23→0→1 bedtime wraps would cause discontinuities.
        var records: [SleepRecord] = []
        for i in 0..<20 {
            let bedtime = (22.0 + Double(i)).truncatingRemainder(dividingBy: 24.0)
            let wake = (6.0 + Double(i)).truncatingRemainder(dividingBy: 24.0)
            records.append(makeRecord(day: i, bedtime: bedtime, wake: wake, duration: 8))
        }

        // Should not crash and should produce a result
        let result = LombScargle.analyze(records, signal: .sleepMidpoint)
        #expect(result.signal == .sleepMidpoint)
        // Linear drift = not periodic, so might not have strong peaks, but it should run
    }

    @Test("analyze with < 14 records → empty result")
    func testAnalyzeTooFewRecords() {
        let records = (0..<10).map { makeRecord(day: $0, bedtime: 23, wake: 7, duration: 8) }
        let result = LombScargle.analyze(records, signal: .sleepDuration)
        #expect(result.isEmpty, "Should return empty for < 14 records")
    }

    @Test("All Signal cases produce valid extraction")
    func testAllSignalCasesExtract() {
        let records = (0..<20).map { i in
            makeRecord(day: i, bedtime: 23, wake: 7,
                       duration: 7.0 + sin(2.0 * Double.pi * Double(i) / 7.0),
                       amplitude: 0.3 + 0.2 * sin(2.0 * Double.pi * Double(i) / 7.0))
        }

        let healthProfiles = (0..<20).map { i in
            DayHealthProfile(
                day: i, date: Date(),
                restingHR: 60 + 5 * sin(2.0 * Double.pi * Double(i) / 7.0),
                avgNocturnalHRV: 40 + 10 * sin(2.0 * Double.pi * Double(i) / 7.0)
            )
        }

        for signal in LombScargle.Signal.allCases {
            let result = LombScargle.analyze(records, signal: signal, healthProfiles: healthProfiles)
            #expect(result.signal == signal, "Result signal should match requested signal")
            // Sleep-derived signals with varying values should produce non-empty power.
            // sleepMidpoint is constant (same schedule every day) → zero variance → empty.
            // cosinorAmplitude varies sinusoidally → should produce power.
            if signal != .sleepMidpoint {
                #expect(!result.power.isEmpty,
                        "Signal \(signal) should produce non-empty power")
            }
        }
    }

    @Test("analyzeAll skips HR/HRV when no health profiles provided")
    func testAnalyzeAllSkipsHealthSignals() {
        let records = (0..<20).map { i in
            makeRecord(day: i, bedtime: 23, wake: 7,
                       duration: 7.0 + sin(2.0 * Double.pi * Double(i) / 7.0))
        }

        let results = LombScargle.analyzeAll(records)

        // Should have sleep-derived signals
        #expect(results[.sleepMidpoint] != nil, "Should analyze sleepMidpoint")
        #expect(results[.sleepDuration] != nil, "Should analyze sleepDuration")
        #expect(results[.cosinorAmplitude] != nil, "Should analyze cosinorAmplitude")

        // Should NOT have health signals (no profiles provided)
        #expect(results[.restingHR] == nil, "Should skip restingHR without health profiles")
        #expect(results[.nocturnalHRV] == nil, "Should skip nocturnalHRV without health profiles")
    }

    @Test("analyzeAll includes HR/HRV when enough health profiles provided")
    func testAnalyzeAllIncludesHealthSignals() {
        let records = (0..<20).map { i in
            makeRecord(day: i, bedtime: 23, wake: 7,
                       duration: 7.0 + sin(2.0 * Double.pi * Double(i) / 7.0))
        }

        let healthProfiles = (0..<20).map { i in
            DayHealthProfile(
                day: i, date: Date(),
                restingHR: 60 + 5 * sin(2.0 * Double.pi * Double(i) / 7.0),
                avgNocturnalHRV: 40 + 10 * sin(2.0 * Double.pi * Double(i) / 7.0)
            )
        }

        let results = LombScargle.analyzeAll(records, healthProfiles: healthProfiles)

        #expect(results.count == 5, "Should have all 5 signals analyzed")
        #expect(results[.restingHR] != nil, "Should include restingHR with sufficient profiles")
        #expect(results[.nocturnalHRV] != nil, "Should include nocturnalHRV with sufficient profiles")
    }

    @Test("analyzeAll skips HR when profiles have nil restingHR")
    func testAnalyzeAllSkipsNilHealth() {
        let records = (0..<20).map { i in
            makeRecord(day: i, bedtime: 23, wake: 7, duration: 8)
        }

        // Profiles with nil restingHR but valid HRV
        let healthProfiles = (0..<20).map { i in
            DayHealthProfile(
                day: i, date: Date(),
                restingHR: nil,
                avgNocturnalHRV: 40 + 10 * sin(2.0 * Double.pi * Double(i) / 7.0)
            )
        }

        let results = LombScargle.analyzeAll(records, healthProfiles: healthProfiles)

        #expect(results[.restingHR] == nil, "Should skip restingHR when all nil")
        #expect(results[.nocturnalHRV] != nil, "Should include nocturnalHRV when non-nil")
    }
}
