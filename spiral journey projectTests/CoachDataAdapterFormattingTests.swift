import Testing
import Foundation
@testable import SpiralKit
@testable import spiral_journey_project

// MARK: - CoachDataAdapter Formatting Tests
//
// Tests cover the pure helper functions that were opened to `internal`
// access. None of these helpers depend on HealthKit, SwiftData, or
// CloudKit, so a real SpiralStore with empty state is sufficient.
//
// SpiralStore is @MainActor, so the whole suite is marked @MainActor.

@MainActor
@Suite("CoachDataAdapter – pure formatting helpers")
struct CoachDataAdapterFormattingTests {

    // A fresh store that starts with no episodes (simulator init injects
    // mock data only when sleepEpisodes is empty AND we are in the simulator;
    // we overwrite episodes immediately after init to isolate each test).
    private func makeAdapter(episodes: [SleepEpisode] = []) -> CoachDataAdapter {
        let store = SpiralStore()
        // Override whatever the init may have loaded/injected.
        store.sleepEpisodes = episodes
        return CoachDataAdapter(store: store)
    }

    // MARK: normalizeBars

    @Test("normalizeBars: [3, 6, 9] → [1/3, 2/3, 1]")
    func testNormalizeBarsBasic() {
        let adapter = makeAdapter()
        let result = adapter.normalizeBars([3, 6, 9])
        #expect(result.count == 3)
        #expect(abs(result[0] - (1.0 / 3.0)) < 0.001)
        #expect(abs(result[1] - (2.0 / 3.0)) < 0.001)
        #expect(abs(result[2] - 1.0) < 0.001)
    }

    @Test("normalizeBars: empty array returns empty")
    func testNormalizeBarsEmpty() {
        let result = makeAdapter().normalizeBars([])
        #expect(result.isEmpty)
    }

    @Test("normalizeBars: all-zero array returns all zeros")
    func testNormalizeBarsAllZero() {
        let result = makeAdapter().normalizeBars([0, 0, 0])
        #expect(result == [0, 0, 0])
    }

    @Test("normalizeBars: single element is always 1.0")
    func testNormalizeBarsOne() {
        let result = makeAdapter().normalizeBars([5])
        #expect(abs(result[0] - 1.0) < 0.001)
    }

    // MARK: sriLabel

    @Test("sriLabel: 0 → irregular")
    func testSriLabel0() {
        #expect(makeAdapter().sriLabel(0) == "irregular")
    }

    @Test("sriLabel: 40 → irregular (boundary inclusive)")
    func testSriLabel40() {
        #expect(makeAdapter().sriLabel(40) == "irregular")
    }

    @Test("sriLabel: 41 → variable")
    func testSriLabel41() {
        #expect(makeAdapter().sriLabel(41) == "variable")
    }

    @Test("sriLabel: 60 → variable (boundary inclusive)")
    func testSriLabel60() {
        #expect(makeAdapter().sriLabel(60) == "variable")
    }

    @Test("sriLabel: 61 → consistente")
    func testSriLabel61() {
        #expect(makeAdapter().sriLabel(61) == "consistente")
    }

    @Test("sriLabel: 80 → consistente (boundary inclusive)")
    func testSriLabel80() {
        #expect(makeAdapter().sriLabel(80) == "consistente")
    }

    @Test("sriLabel: 81 → sólido")
    func testSriLabel81() {
        #expect(makeAdapter().sriLabel(81) == "sólido")
    }

    @Test("sriLabel: 100 → sólido")
    func testSriLabel100() {
        #expect(makeAdapter().sriLabel(100) == "sólido")
    }

    // MARK: formatHour

    @Test("formatHour: 0.5 → 00:30")
    func testFormatHour0_5() {
        #expect(makeAdapter().formatHour(0.5) == "00:30")
    }

    @Test("formatHour: 23.5 → 23:30")
    func testFormatHour23_5() {
        #expect(makeAdapter().formatHour(23.5) == "23:30")
    }

    @Test("formatHour: 0.0 → 00:00")
    func testFormatHour0() {
        #expect(makeAdapter().formatHour(0.0) == "00:00")
    }

    @Test("formatHour: 13.0 → 13:00")
    func testFormatHour13() {
        #expect(makeAdapter().formatHour(13.0) == "13:00")
    }

    @Test("formatHour: 1.25 → 01:15")
    func testFormatHour1_25() {
        #expect(makeAdapter().formatHour(1.25) == "01:15")
    }

    // MARK: chronotypeLabelEs

    @Test("chronotypeLabelEs covers all 5 cases")
    func testChronotypeLabelEsAllCases() {
        let adapter = makeAdapter()
        #expect(adapter.chronotypeLabelEs(.definiteMorning)  == "matutino definido")
        #expect(adapter.chronotypeLabelEs(.moderateMorning)  == "matutino moderado")
        #expect(adapter.chronotypeLabelEs(.intermediate)     == "intermedio")
        #expect(adapter.chronotypeLabelEs(.moderateEvening)  == "nocturno moderado")
        #expect(adapter.chronotypeLabelEs(.definiteEvening)  == "nocturno definido")
    }

    // MARK: lastNBedtimeLatenessNorm
    //
    // The helper maps the clock hour of episode.start to a 0..1 lateness score:
    //   22:00 → 0.0  (earliest, most virtuous bedtime)
    //   01:00 → 0.5  (mid range)
    //   04:00 → 1.0  (latest)
    //
    // ep.start is absolute hours; clock hour = start.truncatingRemainder(by: 24).
    // Use multiples of 24 to pick any desired clock hour:
    //   start = 22          → clock = 22 → 0.0
    //   start = 25          → clock =  1 → 0.5
    //   start = 28          → clock =  4 → 1.0

    @Test("lastNBedtimeLatenessNorm: start=22:00 → 0.0")
    func testBedtimeLatenessEarly() {
        let ep = SleepEpisode(start: 22.0, end: 30.0) // clock 22 → score 0
        let adapter = makeAdapter(episodes: [ep])
        let result = adapter.lastNBedtimeLatenessNorm(n: 1)
        #expect(result.count == 1)
        #expect(abs(result[0] - 0.0) < 0.001,
                "Expected 0.0 for 22:00 bedtime, got \(result[0])")
    }

    @Test("lastNBedtimeLatenessNorm: start=01:00 → ~0.5")
    func testBedtimeLateness01() {
        let ep = SleepEpisode(start: 25.0, end: 33.0) // clock 1 → score 0.5
        let adapter = makeAdapter(episodes: [ep])
        let result = adapter.lastNBedtimeLatenessNorm(n: 1)
        #expect(result.count == 1)
        #expect(abs(result[0] - 0.5) < 0.001,
                "Expected ~0.5 for 01:00 bedtime, got \(result[0])")
    }

    @Test("lastNBedtimeLatenessNorm: start=04:00 → 1.0")
    func testBedtimeLateness04() {
        let ep = SleepEpisode(start: 28.0, end: 36.0) // clock 4 → score 1.0
        let adapter = makeAdapter(episodes: [ep])
        let result = adapter.lastNBedtimeLatenessNorm(n: 1)
        #expect(result.count == 1)
        #expect(abs(result[0] - 1.0) < 0.001,
                "Expected 1.0 for 04:00 bedtime, got \(result[0])")
    }

    @Test("lastNBedtimeLatenessNorm: empty store → empty result")
    func testBedtimeLatenessEmpty() {
        let adapter = makeAdapter(episodes: [])
        let result = adapter.lastNBedtimeLatenessNorm(n: 7)
        #expect(result.isEmpty)
    }

    @Test("lastNBedtimeLatenessNorm: n=3 returns last 3 of 5 episodes")
    func testBedtimeLatenessNTruncation() {
        let episodes = (0..<5).map { i in
            SleepEpisode(start: Double(22 + i * 24), end: Double(30 + i * 24))
        }
        let adapter = makeAdapter(episodes: episodes)
        let result = adapter.lastNBedtimeLatenessNorm(n: 3)
        #expect(result.count == 3)
    }

    @Test("lastNBedtimeLatenessNorm: all values clamped to [0, 1]")
    func testBedtimeLatenessClamp() {
        // Use extreme start hours that might push outside [0, 1] without clamping.
        let extremes = [
            SleepEpisode(start: 18.0, end: 26.0),  // clock 18 — very early, should clamp to 0
            SleepEpisode(start: 29.5, end: 37.5),  // clock  5:30 — past 04:00, should clamp to 1
        ]
        let adapter = makeAdapter(episodes: extremes)
        let result = adapter.lastNBedtimeLatenessNorm(n: 7)
        for v in result {
            #expect(v >= 0.0 && v <= 1.0,
                    "Value \(v) is outside [0, 1]")
        }
    }
}
