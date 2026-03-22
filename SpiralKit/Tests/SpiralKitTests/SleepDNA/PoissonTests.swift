import Testing
import Foundation
@testable import SpiralKit

// MARK: - Helpers

private func makeRecord(
    day: Int,
    bedtime: Double = 23.0,
    wakeup: Double = 7.0,
    awakePhaseCount: Int = 0
) -> SleepRecord {
    // Build phases: fill window with light sleep, then insert awake phases
    var phases: [PhaseInterval] = []
    let windowHours = wakeup > bedtime ? Int(wakeup - bedtime) : Int(wakeup + 24 - bedtime)
    let baseTimestamp = Double(day) * 24.0

    // Generate awake phases at regular intervals within the sleep window
    for i in 0..<awakePhaseCount {
        let hourOffset = Double(i + 1) * (Double(windowHours) / Double(awakePhaseCount + 1))
        let clockHour = (bedtime + hourOffset).truncatingRemainder(dividingBy: 24.0)
        phases.append(PhaseInterval(
            hour: clockHour,
            phase: .awake,
            timestamp: baseTimestamp + hourOffset
        ))
    }
    // Fill remaining with light sleep
    for h in 0..<windowHours {
        let clockHour = (bedtime + Double(h) + 0.5).truncatingRemainder(dividingBy: 24.0)
        phases.append(PhaseInterval(
            hour: clockHour,
            phase: .light,
            timestamp: baseTimestamp + Double(h)
        ))
    }

    return SleepRecord(
        day: day,
        date: Date(),
        isWeekend: day % 7 >= 5,
        bedtimeHour: bedtime,
        wakeupHour: wakeup,
        sleepDuration: Double(windowHours),
        phases: phases,
        hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.1) },
        cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.5),
        driftMinutes: 0
    )
}

// MARK: - Poisson Math Tests

@Suite("PoissonFragmentation — Math")
struct PoissonMathTests {

    @Test("poissonPMF k=0, λ=2 equals exp(-2)")
    func testPMFAtZero() {
        let p = PoissonFragmentation.poissonPMF(k: 0, lambda: 2.0)
        #expect(abs(p - exp(-2.0)) < 1e-12)
    }

    @Test("poissonPMF k=1, λ=1 equals exp(-1)")
    func testPMFAtOne() {
        let p = PoissonFragmentation.poissonPMF(k: 1, lambda: 1.0)
        #expect(abs(p - exp(-1.0)) < 1e-10)
    }

    @Test("poissonPMF sums to ~1 over range 0..20 for λ=3")
    func testPMFSumsToOne() {
        let lambda = 3.0
        let total = (0...20).reduce(0.0) { $0 + PoissonFragmentation.poissonPMF(k: $1, lambda: lambda) }
        #expect(abs(total - 1.0) < 1e-6)
    }

    @Test("poissonCDFComplement k=0 is 1.0")
    func testCDFComplementAtZero() {
        let p = PoissonFragmentation.poissonCDFComplement(k: 0, lambda: 3.0)
        #expect(p == 1.0)
    }

    @Test("poissonCDFComplement k=1 equals 1 - P(X=0)")
    func testCDFComplementAtOne() {
        let lambda = 2.0
        let expected = 1.0 - PoissonFragmentation.poissonPMF(k: 0, lambda: lambda)
        let actual = PoissonFragmentation.poissonCDFComplement(k: 1, lambda: lambda)
        #expect(abs(actual - expected) < 1e-12)
    }

    @Test("poissonCDFComplement is monotonically decreasing in k")
    func testCDFComplementDecreasing() {
        let lambda = 3.0
        var prev = 1.0
        for k in 1...10 {
            let p = PoissonFragmentation.poissonCDFComplement(k: k, lambda: lambda)
            #expect(p <= prev + 1e-12)
            prev = p
        }
    }
}

// MARK: - Baseline Rate Tests

@Suite("PoissonFragmentation — Baseline Rate")
struct PoissonBaselineRateTests {

    @Test("Baseline rate equals mean awakenings")
    func testBaselineRate() {
        // Nights with 1, 2, 3 awakenings → mean = 2
        let records = [
            makeRecord(day: 0, awakePhaseCount: 1),
            makeRecord(day: 1, awakePhaseCount: 2),
            makeRecord(day: 2, awakePhaseCount: 3),
        ]
        let result = PoissonFragmentation.analyze(records: records)
        #expect(abs(result.baselineRate - 2.0) < 1e-10)
    }

    @Test("Zero awakenings → baseline rate is 0")
    func testZeroAwakenings() {
        let records = (0..<5).map { makeRecord(day: $0, awakePhaseCount: 0) }
        let result = PoissonFragmentation.analyze(records: records)
        #expect(result.baselineRate == 0.0)
    }

    @Test("Nightly rates count matches record count")
    func testNightlyRatesCount() {
        let records = (0..<7).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let result = PoissonFragmentation.analyze(records: records)
        #expect(result.nightlyRates.count == 7)
    }

    @Test("Nightly rates preserve day indices")
    func testNightlyRatesDayIndices() {
        let days = [10, 20, 30]
        let records = days.enumerated().map { (i, d) in makeRecord(day: d, awakePhaseCount: i) }
        let result = PoissonFragmentation.analyze(records: records)
        let resultDays = result.nightlyRates.map { $0.day }.sorted()
        #expect(resultDays == days)
    }
}

// MARK: - Anomaly Detection Tests

@Suite("PoissonFragmentation — Anomaly Detection")
struct PoissonAnomalyTests {

    @Test("Night with 6 awakenings is anomalous when baseline is ~1")
    func testHighCountIsAnomalous() {
        // Build 14 nights with 1 awakening each, then add one outlier with 6.
        // With λ = (14*1 + 6)/15 = 1.33, P(X >= 6 | λ=1.33) ≈ 0.003 → anomaly.
        var records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: 1) }
        records.append(makeRecord(day: 14, awakePhaseCount: 6))

        let result = PoissonFragmentation.analyze(records: records)

        // The outlier night should be detected
        #expect(result.anomalousNights.contains(14))
    }

    @Test("Night with same count as baseline is not anomalous")
    func testNormalNightIsNotAnomalous() {
        // All nights have 1 awakening → no anomalies expected (P(X>=1 | λ=1) ≈ 0.63)
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: 1) }
        let result = PoissonFragmentation.analyze(records: records)

        // With uniform data, pValue for k=1 given λ=1 is large (not anomalous)
        let anomalousAmongNormal = result.nightlyRates.filter {
            $0.awakenings == 1 && $0.isAnomaly
        }
        #expect(anomalousAmongNormal.isEmpty)
    }

    @Test("pValue for k=0 given λ=2 equals 1.0")
    func testPValueAtZero() {
        // A night with 0 awakenings when baseline is 2 is not anomalous (right tail)
        let records = [
            makeRecord(day: 0, awakePhaseCount: 0),
            makeRecord(day: 1, awakePhaseCount: 4),
        ]
        let result = PoissonFragmentation.analyze(records: records)
        let zeroNight = result.nightlyRates.first { $0.day == 0 }
        #expect(zeroNight != nil)
        // P(X >= 0) = 1.0 always
        #expect(abs(zeroNight!.pValue - 1.0) < 1e-10)
    }

    @Test("isAnomaly flag matches pValue < 0.05")
    func testIsAnomalyConsistency() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 4) }
        let result = PoissonFragmentation.analyze(records: records)

        for rate in result.nightlyRates {
            #expect(rate.isAnomaly == (rate.pValue < 0.05))
        }
    }
}

// MARK: - Chi-Squared Tests

@Suite("PoissonFragmentation — Chi-Squared")
struct PoissonChiSquaredTests {

    @Test("Poisson-distributed data passes chi-squared test")
    func testPoissonDataPasses() {
        // Simulate Poisson(λ=2) counts: use rounded values from a known distribution
        // Expected frequencies for 30 samples: 0,1,2,3,4+ from Poisson(2)
        // P(0)≈0.135, P(1)≈0.271, P(2)≈0.271, P(3)≈0.180, P(4+)≈0.143
        // Build an approximate Poisson sample:
        let counts = [0,0,0,0, 1,1,1,1,1,1,1,1, 2,2,2,2,2,2,2,2, 3,3,3,3,3,3, 4,4,4,4]
        let records = counts.enumerated().map { (i, c) in makeRecord(day: i, awakePhaseCount: c) }

        let result = PoissonFragmentation.analyze(records: records)
        // A Poisson distribution should have p > 0.05
        #expect(result.followsPoisson)
        #expect(result.chiSquaredPValue > 0.05)
    }

    @Test("All-same-count data fails chi-squared test for non-trivial lambda")
    func testUniformDataFails() {
        // All nights have exactly 3 awakenings — this is far too uniform for Poisson
        let records = (0..<20).map { makeRecord(day: $0, awakePhaseCount: 3) }
        let result = PoissonFragmentation.analyze(records: records)
        // A Poisson with λ=3 predicts lots of spread, but all counts are exactly 3
        #expect(!result.followsPoisson || result.chiSquaredPValue <= 0.05)
    }

    @Test("chiSquaredPValue is in [0, 1]")
    func testChiSquaredPValueRange() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let result = PoissonFragmentation.analyze(records: records)
        #expect(result.chiSquaredPValue >= 0.0)
        #expect(result.chiSquaredPValue <= 1.0)
    }

    @Test("followsPoisson is consistent with chiSquaredPValue")
    func testFollowsPoissonConsistency() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 4) }
        let result = PoissonFragmentation.analyze(records: records)
        #expect(result.followsPoisson == (result.chiSquaredPValue > 0.05))
    }
}

// MARK: - Codability

@Suite("PoissonFragmentation — Codable")
struct PoissonCodableTests {

    @Test("PoissonFragmentationResult is Codable")
    func testCodable() throws {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let result = PoissonFragmentation.analyze(records: records)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PoissonFragmentationResult.self, from: data)

        #expect(decoded.baselineRate == result.baselineRate)
        #expect(decoded.nightlyRates.count == result.nightlyRates.count)
        #expect(decoded.anomalousNights == result.anomalousNights)
        #expect(decoded.chiSquaredPValue == result.chiSquaredPValue)
        #expect(decoded.followsPoisson == result.followsPoisson)
    }

    @Test("DayRate is Codable")
    func testDayRateCodable() throws {
        let rate = DayRate(day: 5, awakenings: 3, expectedRate: 2.0, pValue: 0.32, isAnomaly: false)
        let data = try JSONEncoder().encode(rate)
        let decoded = try JSONDecoder().decode(DayRate.self, from: data)
        #expect(decoded.day == rate.day)
        #expect(decoded.awakenings == rate.awakenings)
        #expect(decoded.expectedRate == rate.expectedRate)
        #expect(decoded.pValue == rate.pValue)
        #expect(decoded.isAnomaly == rate.isAnomaly)
    }
}

// MARK: - Integration with SleepDNAComputer

@Suite("PoissonFragmentation — Computer Integration")
struct PoissonComputerIntegrationTests {

    private func makeRecords(count: Int, awakePerNight: Int = 2) -> [SleepRecord] {
        (0..<count).map { makeRecord(day: $0, awakePhaseCount: awakePerNight) }
    }

    @Test("Intermediate tier (28 records) has poissonFragmentation")
    func testIntermediateTierHasPoisson() async throws {
        let records = makeRecords(count: 28)
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .intermediate)
        #expect(profile.poissonFragmentation != nil)
        #expect(profile.poissonFragmentation!.nightlyRates.count == 28)
    }

    @Test("Basic tier (14 records) has no poissonFragmentation")
    func testBasicTierNoPoisson() async throws {
        let records = makeRecords(count: 14)
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .basic)
        #expect(profile.poissonFragmentation == nil)
    }

    @Test("Full tier (60 records) has both poissonFragmentation and hawkesAnalysis nil events")
    func testFullTierHasBothResults() async throws {
        let records = makeRecords(count: 60)
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .full)
        #expect(profile.poissonFragmentation != nil)
        #expect(profile.hawkesAnalysis != nil)
    }
}
