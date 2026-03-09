import Testing
@testable import SpiralKit

@Suite("ConclusionsEngine")
struct ConclusionsTests {

    private func makeStats(sri: Double = 80, rhythmStability: Double = 0.8,
                           sleepDuration: Double = 7.5, socialJetlag: Double = 20,
                           meanR2: Double = 0.75, ampDrop: Double = 5) -> SleepStats {
        SleepStats(
            meanAcrophase: 15, stdAcrophase: 0.8,
            meanAmplitude: 0.35, rhythmStability: rhythmStability,
            socialJetlag: socialJetlag,
            weekdayAmp: 0.36, weekendAmp: 0.34,
            ampDrop: ampDrop,
            meanSleepDuration: sleepDuration,
            meanR2: meanR2,
            sri: sri
        )
    }

    @Test("Composite score is in [0, 100]")
    func testCompositeRange() {
        let good = makeStats()
        let poor = makeStats(sri: 20, rhythmStability: 0.1, sleepDuration: 4, socialJetlag: 200)
        #expect(ConclusionsEngine.compositeScore(stats: good) <= 100)
        #expect(ConclusionsEngine.compositeScore(stats: poor) >= 0)
    }

    @Test("Perfect stats produce high composite score")
    func testHighScore() {
        let stats = makeStats(sri: 95, rhythmStability: 0.95, sleepDuration: 7.5,
                              socialJetlag: 10, meanR2: 0.9, ampDrop: 2)
        let score = ConclusionsEngine.compositeScore(stats: stats)
        #expect(score >= 70, "Good stats should score ≥ 70, got \(score)")
    }

    @Test("Poor stats produce low composite score")
    func testLowScore() {
        let stats = makeStats(sri: 20, rhythmStability: 0.1, sleepDuration: 4.5,
                              socialJetlag: 180, meanR2: 0.2, ampDrop: 40)
        let score = ConclusionsEngine.compositeScore(stats: stats)
        #expect(score < 60, "Poor stats should score < 60, got \(score)")
    }

    @Test("Score labels match ranges")
    func testScoreLabels() {
        #expect(ConclusionsEngine.scoreLabel(90) == "Excellent")
        #expect(ConclusionsEngine.scoreLabel(75) == "Good")
        #expect(ConclusionsEngine.scoreLabel(55) == "Moderate")
        #expect(ConclusionsEngine.scoreLabel(30) == "Needs Attention")
    }

    @Test("Evaluate categories returns 6 categories")
    func testCategoryCount() {
        let stats = makeStats()
        let sigs = [DisorderSignature(id: "normal", label: "Normal", fullLabel: "Normal",
                                     confidence: 0.8, description: "ok", hexColor: "#5bffa8")]
        let cats = ConclusionsEngine.evaluateCategories(stats: stats, signatures: sigs)
        #expect(cats.count == 6)
        let ids = Set(cats.map(\.id))
        #expect(ids.contains("duration"))
        #expect(ids.contains("regularity"))
        #expect(ids.contains("rhythm"))
        #expect(ids.contains("jetlag"))
        #expect(ids.contains("pattern"))
        #expect(ids.contains("timing"))
    }

    @Test("Generate returns non-empty result for empty records")
    func testGenerateEmpty() {
        let result = ConclusionsEngine.generate(from: [])
        #expect(result.composite >= 0)
        #expect(result.composite <= 100)
    }
}
