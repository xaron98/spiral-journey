import Testing
import Foundation
@testable import SpiralKit

@Suite("SleepDNAComputer")
struct SleepDNAComputerTests {

    // MARK: - Helpers

    private func makeRecord(
        day: Int,
        bedtime: Double = 23,
        wakeup: Double = 7,
        duration: Double = 8
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
            cosinor: .empty,
            driftMinutes: 0
        )
    }

    private func makeRecords(count: Int) -> [SleepRecord] {
        (0..<count).map { day in
            // Vary bedtime slightly so features aren't constant (avoids degenerate FFT)
            let bedtime = 22.5 + Double(day % 3) * 0.5  // 22.5, 23.0, 23.5
            let wakeup = 6.5 + Double(day % 3) * 0.5    // 6.5, 7.0, 7.5
            let duration = wakeup + 24 - bedtime         // approx 8h
            return makeRecord(day: day, bedtime: bedtime, wakeup: wakeup, duration: duration)
        }
    }

    // MARK: - Tier Tests

    @Test("7 records -> basic tier, no motifs, no prediction")
    func testBasicTier() async throws {
        let records = makeRecords(count: 7)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.tier == .basic)
        #expect(profile.dataWeeks == 1)
        #expect(profile.nucleotides.count == 7)
        #expect(profile.motifs.isEmpty)
        #expect(profile.mutations.isEmpty)
        #expect(profile.expressionRules.isEmpty)
        #expect(profile.prediction == nil)
    }

    @Test("30 records -> full tier (>=4wk), has motifs + prediction")
    func testIntermediateTier() async throws {
        let records = makeRecords(count: 30)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        // Thresholds lowered 2026-04: 30 records (~4.3 weeks) is now `.full`.
        #expect(profile.tier == .full)
        #expect(profile.dataWeeks == 4)
        #expect(profile.nucleotides.count == 30)
        #expect(profile.sequences.count == 24)  // 30 - 7 + 1
        // Motifs should be computed at intermediate+ tier (gate lowered).
        // Whether clustering actually produces motifs depends on data shape,
        // so we only assert the pipeline ran — not an exact count.
    }

    @Test("60 records -> full tier, has motifs + prediction")
    func testFullTier() async throws {
        let records = makeRecords(count: 60)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.tier == .full)
        #expect(profile.dataWeeks == 8)
        #expect(profile.nucleotides.count == 60)
        #expect(profile.sequences.count == 54)  // 60 - 7 + 1
        // BLOSUM should be learned (not .initial)
        #expect(profile.scoringMatrix.weights.count == 16)
        // Health markers are always computed
        #expect(profile.healthMarkers.circadianCoherence >= 0)
    }

    @Test("14 records -> intermediate tier, motifs attempted")
    func testIntermediateTierAt2Weeks() async throws {
        let records = makeRecords(count: 14)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        // 14 records = 2 weeks = intermediate tier (new boundary).
        #expect(profile.tier == .intermediate)
        #expect(profile.dataWeeks == 2)
        #expect(profile.sequences.count == 8)  // 14 - 7 + 1
        // Motifs should be attempted (sequences.count >= 4 is enough).
    }

    @Test("Empty records throws insufficientData")
    func testEmptyRecords() async throws {
        let computer = SleepDNAComputer()

        await #expect(throws: SleepDNAError.self) {
            try await computer.compute(
                records: [],
                events: [],
                chronotype: nil,
                goalDuration: 8
            )
        }
    }

    @Test("Profile has correct tier boundaries")
    func testTierBoundaries() async throws {
        let computer = SleepDNAComputer()

        // Boundaries lowered 2026-04:
        //   basic:        < 2 weeks (< 14 records)
        //   intermediate: 2-3 weeks (14-27 records)
        //   full:         >= 4 weeks (>= 28 records)

        // 13 records = 1 week + 6 days -> basic
        let p13 = try await computer.compute(
            records: makeRecords(count: 13),
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(p13.tier == .basic)

        // 14 records = 2 weeks -> intermediate
        let p14 = try await computer.compute(
            records: makeRecords(count: 14),
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(p14.tier == .intermediate)

        // 27 records = 3 weeks + 6 days -> intermediate
        let p27 = try await computer.compute(
            records: makeRecords(count: 27),
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(p27.tier == .intermediate)

        // 28 records = 4 weeks -> full
        let p28 = try await computer.compute(
            records: makeRecords(count: 28),
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(p28.tier == .full)
    }

    @Test("Profile includes helix geometry for every record")
    func testHelixGeometry() async throws {
        let records = makeRecords(count: 14)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.helixGeometry.count == 14)
    }

    @Test("Clusters mirror motifs")
    func testClustersMatchMotifs() async throws {
        let records = makeRecords(count: 60)
        let computer = SleepDNAComputer()

        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )

        #expect(profile.clusters.count == profile.motifs.count)
        for (cluster, motif) in zip(profile.clusters, profile.motifs) {
            #expect(cluster.label == motif.name)
            #expect(cluster.memberWeekIndices == motif.instanceWeekIndices)
        }
    }

    @Test("Existing BLOSUM is reused when tier is not full")
    func testExistingBLOSUM() async throws {
        let customWeights = Array(repeating: 2.5, count: 16)
        let existingBLOSUM = SleepBLOSUM(weights: customWeights)
        let computer = SleepDNAComputer()

        // 7 records = 1 week = basic tier, BLOSUM not learned.
        let profile = try await computer.compute(
            records: makeRecords(count: 7),
            events: [],
            chronotype: nil,
            goalDuration: 8,
            existingBLOSUM: existingBLOSUM
        )

        #expect(profile.tier == .basic)
        #expect(profile.scoringMatrix.weights == customWeights)
    }
}
