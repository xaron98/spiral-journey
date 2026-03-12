import Testing
import Foundation
@testable import SpiralKit

// MARK: - ManualDataConverter

@Suite("ManualDataConverter")
struct ManualDataConverterTests {

    /// One simple episode: day 0, 23:00 → 07:00 next day (8 h crossing midnight).
    private let singleEpisode = SleepEpisode(start: 23.0, end: 31.0) // 23h → 07h day1

    @Test("Produces one record per requested day")
    func testRecordCount() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 7)
        #expect(records.count == 7)
    }

    @Test("Day indices are consecutive starting at 0")
    func testDayIndices() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 5)
        for (i, r) in records.enumerated() {
            #expect(r.day == i)
        }
    }

    @Test("Hourly activity has 24 entries per record")
    func testHourlyActivityCount() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 3)
        for r in records {
            #expect(r.hourlyActivity.count == 24)
        }
    }

    @Test("Activity is 0.05 during sleep and 0.95 while awake")
    func testActivityValues() {
        // Episode covers absolute hours 23-31 → day 0 h23 and day 1 h0-h6
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 2)

        // Day 0: hour 23 should be sleeping
        let day0 = records[0]
        #expect(day0.hourlyActivity[23].activity == 0.05,
                "Day 0 h23 should be sleeping (0.05), got \(day0.hourlyActivity[23].activity)")
        // Day 0: hour 12 should be awake
        #expect(day0.hourlyActivity[12].activity == 0.95,
                "Day 0 h12 should be awake (0.95)")

        // Day 1: hour 6 should be sleeping (episode ends at 31 = 07:00 day1, so h6 is still in)
        let day1 = records[1]
        #expect(day1.hourlyActivity[6].activity == 0.05,
                "Day 1 h6 should be sleeping")
        // Day 1: hour 8 should be awake
        #expect(day1.hourlyActivity[8].activity == 0.95,
                "Day 1 h8 should be awake")
    }

    @Test("Sleep duration matches episode overlap with each day")
    func testSleepDuration() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 2)
        // Day 0: episode 23-31 overlaps day 0 (0-24) from 23 to 24 → 1h
        #expect(abs(records[0].sleepDuration - 1.0) < 0.01,
                "Day 0 should have 1h sleep, got \(records[0].sleepDuration)")
        // Day 1: episode 23-31 overlaps day 1 (24-48) from 24 to 31 → 7h
        #expect(abs(records[1].sleepDuration - 7.0) < 0.01,
                "Day 1 should have 7h sleep, got \(records[1].sleepDuration)")
    }

    @Test("Phase intervals cover 24 hours at 15-min resolution (96 intervals)")
    func testPhaseIntervalCount() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 1)
        #expect(records[0].phases.count == 96,
                "Expected 96 phase intervals (24h × 4), got \(records[0].phases.count)")
    }

    @Test("Phases during sleep are .deep for manual episodes (no phase set)")
    func testManualEpisodePhaseFallback() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 1)
        // Day 0, t=23.0 (hour 23) → sleeping → should be .deep
        let sleepInterval = records[0].phases.first { $0.hour == 23.0 }
        #expect(sleepInterval?.phase == .deep,
                "Manual episodes without phase should fall back to .deep")
    }

    @Test("HealthKit phase is preserved when set on episode")
    func testHealthKitPhasePreserved() {
        let remEpisode = SleepEpisode(start: 23.0, end: 31.0, phase: .rem)
        let records = ManualDataConverter.convert(episodes: [remEpisode], numDays: 1)
        let sleepInterval = records[0].phases.first { $0.hour == 23.0 }
        #expect(sleepInterval?.phase == .rem,
                "HealthKit REM phase should be preserved")
    }

    @Test("Awake phases outside any episode are .awake")
    func testAwakePhaseOutsideEpisode() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 1)
        // Day 0, t=12.0 → no episode covers this → .awake
        let awakeInterval = records[0].phases.first { $0.hour == 12.0 }
        #expect(awakeInterval?.phase == .awake,
                "Hour 12 with no episode should be .awake")
    }

    @Test("First record has zero drift; subsequent drifts are finite")
    func testDriftMinutes() {
        // Two episodes with slightly different timing to produce drift
        let ep1 = SleepEpisode(start: 23.0, end: 31.0)
        let ep2 = SleepEpisode(start: 47.5, end: 55.5) // day 1, 23:30 → 07:30
        let records = ManualDataConverter.convert(episodes: [ep1, ep2], numDays: 3)
        #expect(records[0].driftMinutes == 0.0)
        // Drift on day 1 should be a finite number (not NaN/inf)
        #expect(records[1].driftMinutes.isFinite)
    }

    @Test("No episodes → sleep duration is 0 for all records")
    func testNoEpisodesZeroDuration() {
        let records = ManualDataConverter.convert(episodes: [], numDays: 3)
        for r in records {
            #expect(r.sleepDuration == 0.0)
        }
    }

    @Test("Zero numDays returns empty array")
    func testZeroDays() {
        let records = ManualDataConverter.convert(episodes: [singleEpisode], numDays: 0)
        #expect(records.isEmpty)
    }
}

// MARK: - SleepEpisode Codable

@Suite("SleepEpisode Codable")
struct SleepEpisodeCodableTests {

    @Test("SleepEpisode survives JSON round-trip")
    func testRoundTrip() throws {
        let original = SleepEpisode(
            start: 23.5,
            end: 31.0,
            source: .healthKit,
            healthKitSampleID: "abc-123",
            phase: .rem
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepEpisode.self, from: data)

        #expect(decoded.start == original.start)
        #expect(decoded.end == original.end)
        #expect(decoded.source == original.source)
        #expect(decoded.healthKitSampleID == original.healthKitSampleID)
        #expect(decoded.phase == original.phase)
        #expect(decoded.id == original.id)
    }

    @Test("Array of episodes survives JSON round-trip")
    func testArrayRoundTrip() throws {
        let episodes: [SleepEpisode] = [
            SleepEpisode(start: 23.0, end: 31.0, phase: .deep),
            SleepEpisode(start: 47.0, end: 55.0, phase: .light),
            SleepEpisode(start: 71.5, end: 79.5)
        ]
        let data = try JSONEncoder().encode(episodes)
        let decoded = try JSONDecoder().decode([SleepEpisode].self, from: data)
        #expect(decoded.count == 3)
        #expect(decoded[0].phase == .deep)
        #expect(decoded[1].phase == .light)
        #expect(decoded[2].phase == nil)
    }

    @Test("Duration computed property matches end - start")
    func testDuration() {
        let ep = SleepEpisode(start: 23.0, end: 31.5)
        #expect(ep.duration == 8.5)
    }

    @Test("Manual source is default")
    func testDefaultSource() {
        let ep = SleepEpisode(start: 0, end: 8)
        #expect(ep.source == .manual)
    }

    @Test("Phase nil by default for manual episode")
    func testDefaultPhaseNil() {
        let ep = SleepEpisode(start: 0, end: 8)
        #expect(ep.phase == nil)
    }
}

// MARK: - SleepRecord Codable

@Suite("SleepRecord Codable")
struct SleepRecordCodableTests {

    private func makeRecord() -> SleepRecord {
        SleepRecord(
            day: 0,
            date: Date(timeIntervalSince1970: 0),
            isWeekend: false,
            bedtimeHour: 23.0,
            wakeupHour: 7.0,
            sleepDuration: 8.0,
            phases: [PhaseInterval(hour: 0, phase: .deep, timestamp: 0)],
            hourlyActivity: [HourlyActivity(hour: 0, activity: 0.1)],
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.8),
            driftMinutes: 15.0
        )
    }

    @Test("SleepRecord survives JSON round-trip")
    func testRoundTrip() throws {
        let original = makeRecord()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SleepRecord.self, from: data)

        #expect(decoded.day == original.day)
        #expect(decoded.bedtimeHour == original.bedtimeHour)
        #expect(decoded.wakeupHour == original.wakeupHour)
        #expect(decoded.sleepDuration == original.sleepDuration)
        #expect(decoded.driftMinutes == original.driftMinutes)
        #expect(decoded.phases.count == original.phases.count)
        #expect(decoded.hourlyActivity.count == original.hourlyActivity.count)
        #expect(decoded.cosinor.acrophase == original.cosinor.acrophase)
        #expect(decoded.id == original.id)
    }
}
