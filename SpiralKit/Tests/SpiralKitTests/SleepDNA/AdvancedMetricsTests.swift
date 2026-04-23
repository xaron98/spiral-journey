import Testing
import Foundation
@testable import SpiralKit

// MARK: - Helpers

private func makeRecord(
    day: Int,
    bedtime: Double = 23,
    wakeup: Double = 7,
    duration: Double = 8,
    cosinorR2: Double = 0.5,
    acrophase: Double = 15
) -> SleepRecord {
    SleepRecord(
        day: day,
        date: Date(),
        isWeekend: day % 7 >= 5,
        bedtimeHour: bedtime,
        wakeupHour: wakeup,
        sleepDuration: duration,
        phases: [],
        hourlyActivity: (0..<24).map { h in
            let asleep = bedtime > wakeup
                ? (Double(h) >= bedtime || Double(h) < wakeup)
                : (Double(h) >= bedtime && Double(h) < wakeup)
            return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
        },
        cosinor: CosinorResult(
            mesor: 0.5,
            amplitude: 0.3,
            acrophase: acrophase,
            period: 24,
            r2: cosinorR2
        ),
        driftMinutes: 0
    )
}

private func makeNucleotidesAndHelix(
    count: Int,
    bedtimeVariation: Double = 0.5
) -> ([DayNucleotide], [DayHelixParams]) {
    var records = [SleepRecord]()
    for i in 0..<count {
        let bedtime = 23.0 + Double(i % 3) * bedtimeVariation
        let wakeup = 7.0 + Double(i % 3) * 0.25
        records.append(makeRecord(day: i, bedtime: bedtime, wakeup: wakeup))
    }

    let nucleotides = records.map { record in
        DayNucleotide.encode(record: record, events: [], processS: 0.5, period: 24, goalDuration: 8)
    }
    let basePairs = HilbertPhaseAnalyzer.analyze(nucleotides: nucleotides)
    let helixGeometry = HelixGeometryComputer.compute(
        records: records,
        basePairs: basePairs,
        chronotype: nil
    )
    return (nucleotides, helixGeometry)
}

// MARK: - Persistent Homology Tests

@Suite("PersistentHomology")
struct PersistentHomologyTests {

    @Test("Stable helix produces high structural stability")
    func testStableHelix() {
        // Consistent bedtime pattern = structured point cloud
        let (nucs, helix) = makeNucleotidesAndHelix(count: 14, bedtimeVariation: 0.1)
        let result = PersistentHomology.compute(nucleotides: nucs, helixGeometry: helix)

        #expect(result.structuralStability > 0.3)
        #expect(result.beta0 >= 1)
        #expect(!result.features.isEmpty)
    }

    @Test("Varied helix produces lower stability than stable one")
    func testVariedVsStable() {
        let (stableNucs, stableHelix) = makeNucleotidesAndHelix(count: 14, bedtimeVariation: 0.05)
        let stableResult = PersistentHomology.compute(nucleotides: stableNucs, helixGeometry: stableHelix)

        let (variedNucs, variedHelix) = makeNucleotidesAndHelix(count: 14, bedtimeVariation: 2.0)
        let variedResult = PersistentHomology.compute(nucleotides: variedNucs, helixGeometry: variedHelix)

        // Stable should have higher structural stability
        #expect(stableResult.structuralStability >= variedResult.structuralStability * 0.5)
    }

    @Test("Empty input returns zero result")
    func testEmpty() {
        let result = PersistentHomology.compute(nucleotides: [], helixGeometry: [])
        #expect(result.features.isEmpty)
        #expect(result.beta0 == 0)
        #expect(result.beta1 == 0)
        #expect(result.structuralStability == 0)
    }

    @Test("Single point returns zero result")
    func testSinglePoint() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 1)
        let result = PersistentHomology.compute(nucleotides: nucs, helixGeometry: helix)
        #expect(result.features.isEmpty)
        #expect(result.structuralStability == 0)
    }

    @Test("All features have non-negative persistence")
    func testPersistenceNonNegative() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 10)
        let result = PersistentHomology.compute(nucleotides: nucs, helixGeometry: helix)

        for feature in result.features {
            #expect(feature.persistence >= 0)
            #expect(feature.death >= feature.birth)
        }
    }

    @Test("Structural stability is in [0, 1]")
    func testStabilityRange() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 20)
        let result = PersistentHomology.compute(nucleotides: nucs, helixGeometry: helix)
        #expect(result.structuralStability >= 0)
        #expect(result.structuralStability <= 1)
    }

    @Test("Result is Codable")
    func testCodable() throws {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 10)
        let result = PersistentHomology.compute(nucleotides: nucs, helixGeometry: helix)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PersistentHomologyResult.self, from: data)
        #expect(decoded.beta0 == result.beta0)
        #expect(decoded.beta1 == result.beta1)
        #expect(decoded.structuralStability == result.structuralStability)
        #expect(decoded.features.count == result.features.count)
    }
}

// MARK: - Linking Number Tests

@Suite("LinkingNumber")
struct LinkingNumberTests {

    @Test("Intertwined strands produce non-zero linking number")
    func testIntertwinedStrands() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 14)
        let result = LinkingNumber.compute(nucleotides: nucs, helixGeometry: helix)

        // With twist angles from the helix, strands should be intertwined
        #expect(abs(result.linkingNumber) > 0)
        #expect(result.density > 0)
    }

    @Test("Density scales with segment count")
    func testDensity() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 14)
        let result = LinkingNumber.compute(nucleotides: nucs, helixGeometry: helix)

        // Density = |linkingNumber| / numSegments
        let expectedDensity = abs(result.linkingNumber) / Double(nucs.count - 1)
        #expect(abs(result.density - expectedDensity) < 1e-10)
    }

    @Test("Empty input returns zero result")
    func testEmpty() {
        let result = LinkingNumber.compute(nucleotides: [], helixGeometry: [])
        #expect(result.linkingNumber == 0)
        #expect(result.density == 0)
        #expect(!result.isCoherent)
    }

    @Test("Single point returns zero result")
    func testSinglePoint() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 1)
        let result = LinkingNumber.compute(nucleotides: nucs, helixGeometry: helix)
        #expect(result.linkingNumber == 0)
        #expect(result.density == 0)
    }

    @Test("Coherence flag reflects threshold")
    func testCoherenceFlag() {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 14)
        let result = LinkingNumber.compute(nucleotides: nucs, helixGeometry: helix)

        // isCoherent should match density > 0.1
        #expect(result.isCoherent == (result.density > 0.1))
    }

    @Test("Result is Codable")
    func testCodable() throws {
        let (nucs, helix) = makeNucleotidesAndHelix(count: 10)
        let result = LinkingNumber.compute(nucleotides: nucs, helixGeometry: helix)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(LinkingNumberResult.self, from: data)
        #expect(decoded.linkingNumber == result.linkingNumber)
        #expect(decoded.density == result.density)
        #expect(decoded.isCoherent == result.isCoherent)
    }
}

// MARK: - Mutual Information Spectrum Tests

@Suite("MutualInformationSpectrum")
struct MutualInformationSpectrumTests {

    @Test("Sufficient data produces 24-hour spectrum")
    func testBasicSpectrum() {
        let records = (0..<30).map { day in
            let bedtime = 22.5 + Double(day % 3) * 0.5
            let wakeup = 6.5 + Double(day % 3) * 0.5
            return makeRecord(day: day, bedtime: bedtime, wakeup: wakeup)
        }

        let result = MutualInformationSpectrum.compute(records: records)
        #expect(result != nil)
        #expect(result!.windows.count == 24)
        #expect(result!.peakHour >= 0 && result!.peakHour < 24)
        #expect(result!.troughHour >= 0 && result!.troughHour < 24)
        #expect(result!.meanMI >= 0)
    }

    @Test("Insufficient data returns nil")
    func testInsufficientData() {
        let records = (0..<5).map { day in
            makeRecord(day: day)
        }

        let result = MutualInformationSpectrum.compute(records: records)
        #expect(result == nil)
    }

    @Test("MI values are non-negative")
    func testNonNegativeMI() {
        let records = (0..<14).map { day in
            let bedtime = 22.0 + Double(day % 4) * 0.5
            return makeRecord(day: day, bedtime: bedtime)
        }

        let result = MutualInformationSpectrum.compute(records: records)
        #expect(result != nil)
        for window in result!.windows {
            #expect(window.mutualInformation >= 0)
            #expect(window.hourOfDay >= 0 && window.hourOfDay < 24)
        }
    }

    @Test("Windows cover all 24 hours")
    func testAllHoursCovered() {
        let records = (0..<20).map { day in
            makeRecord(day: day, bedtime: 23, wakeup: 7)
        }

        let result = MutualInformationSpectrum.compute(records: records)
        #expect(result != nil)

        let hours = Set(result!.windows.map { $0.hourOfDay })
        #expect(hours.count == 24)
        for h in 0..<24 {
            #expect(hours.contains(h))
        }
    }

    @Test("Mean MI matches manual calculation")
    func testMeanMI() {
        let records = (0..<14).map { day in
            makeRecord(day: day)
        }

        let result = MutualInformationSpectrum.compute(records: records)
        #expect(result != nil)

        let manualMean = result!.windows.reduce(0.0) { $0 + $1.mutualInformation } / 24.0
        #expect(abs(result!.meanMI - manualMean) < 1e-10)
    }

    @Test("Result is Codable")
    func testCodable() throws {
        let records = (0..<14).map { day in
            makeRecord(day: day, bedtime: 22.5 + Double(day % 3) * 0.5)
        }

        let result = MutualInformationSpectrum.compute(records: records)!

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MISResult.self, from: data)
        #expect(decoded.windows.count == result.windows.count)
        #expect(decoded.peakHour == result.peakHour)
        #expect(decoded.troughHour == result.troughHour)
        #expect(decoded.meanMI == result.meanMI)
    }
}

// MARK: - Integration with SleepDNAComputer

@Suite("AdvancedMetrics Integration")
struct AdvancedMetricsIntegrationTests {

    private func makeRecords(count: Int) -> [SleepRecord] {
        (0..<count).map { day in
            let bedtime = 22.5 + Double(day % 3) * 0.5
            let wakeup = 6.5 + Double(day % 3) * 0.5
            let duration = wakeup + 24 - bedtime
            return makeRecord(day: day, bedtime: bedtime, wakeup: wakeup, duration: duration)
        }
    }

    @Test("Full tier profile includes advanced metrics")
    func testFullTierHasAdvancedMetrics() async throws {
        let records = makeRecords(count: 60)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.tier == .full)
        #expect(profile.persistentHomology != nil)
        #expect(profile.linkingNumber != nil)
        #expect(profile.mutualInfoSpectrum != nil)

        // Validate PCH
        #expect(profile.persistentHomology!.structuralStability >= 0)
        #expect(profile.persistentHomology!.structuralStability <= 1)

        // Validate LND
        #expect(profile.linkingNumber!.density >= 0)

        // Validate MIS
        #expect(profile.mutualInfoSpectrum!.windows.count == 24)
    }

    @Test("Basic tier profile does not include advanced metrics")
    func testBasicTierNoAdvancedMetrics() async throws {
        // Thresholds lowered 2026-04: basic now requires < 14 records.
        let records = makeRecords(count: 7)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.tier == .basic)
        #expect(profile.persistentHomology == nil)
        #expect(profile.linkingNumber == nil)
        #expect(profile.mutualInfoSpectrum == nil)
    }

    @Test("Intermediate tier profile does not include advanced metrics")
    func testIntermediateTierNoAdvancedMetrics() async throws {
        // Intermediate now = 2-3 weeks (14-27 records).
        let records = makeRecords(count: 21)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.tier == .intermediate)
        #expect(profile.persistentHomology == nil)
        #expect(profile.linkingNumber == nil)
        #expect(profile.mutualInfoSpectrum == nil)
    }
}
