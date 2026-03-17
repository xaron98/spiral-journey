import Testing
import Foundation
@testable import SpiralKit

@Suite("SequenceAlignmentEngine")
struct SequenceAlignmentTests {

    // MARK: - Helpers

    /// Create a DayNucleotide with explicit features.
    private func makeNucleotide(day: Int, features: [Double]) -> DayNucleotide {
        DayNucleotide(day: day, features: features)
    }

    /// Create a nucleotide encoding a specific bedtime and wake time.
    ///
    /// Features:
    /// - 0: sin(2pi * bedtime/24)
    /// - 1: cos(2pi * bedtime/24)
    /// - 2: sin(2pi * wake/24)
    /// - 3: cos(2pi * wake/24)
    /// - 4: duration / 12.0
    /// - 5-15: 0.5 (neutral)
    private func makeTimingNucleotide(day: Int, bedtime: Double, wake: Double) -> DayNucleotide {
        var features = [Double](repeating: 0.5, count: 16)
        let bedRad = 2.0 * Double.pi * bedtime / 24.0
        features[0] = sin(bedRad)
        features[1] = cos(bedRad)
        let wakeRad = 2.0 * Double.pi * wake / 24.0
        features[2] = sin(wakeRad)
        features[3] = cos(wakeRad)
        // Duration: typical sleep hours / 12.0
        let duration: Double
        if wake > bedtime {
            duration = wake - bedtime
        } else {
            duration = (24.0 - bedtime) + wake
        }
        features[4] = min(duration / 12.0, 1.0)
        return DayNucleotide(day: day, features: features)
    }

    /// Create a week of nucleotides with constant features.
    private func makeConstantWeek(startDay: Int, value: Double) -> WeekSequence {
        let nucs = (0..<7).map { i in
            makeNucleotide(day: startDay + i, features: Array(repeating: value, count: 16))
        }
        return WeekSequence(startDay: startDay, nucleotides: nucs)
    }

    /// Create a week with consistent bedtime/wake pattern.
    private func makeTimingWeek(startDay: Int, bedtime: Double, wake: Double) -> WeekSequence {
        let nucs = (0..<7).map { i in
            makeTimingNucleotide(day: startDay + i, bedtime: bedtime, wake: wake)
        }
        return WeekSequence(startDay: startDay, nucleotides: nucs)
    }

    /// Build a history of weeks with a repeating pattern.
    private func makeRepeatingHistory(
        bedtime: Double,
        wake: Double,
        weekCount: Int,
        startDay: Int = 0
    ) -> [WeekSequence] {
        (0..<weekCount).map { w in
            makeTimingWeek(startDay: startDay + w * 7, bedtime: bedtime, wake: wake)
        }
    }

    // MARK: - Minimum data guards

    @Test("Returns nil with fewer than 2 current days")
    func testTooFewCurrentDays() {
        let oneDay = [makeTimingNucleotide(day: 0, bedtime: 23, wake: 7)]
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 4)

        let result = SequenceAlignmentEngine.predict(
            currentDays: oneDay,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result == nil, "Should return nil with < 2 current days")
    }

    @Test("Returns nil with 0 current days")
    func testZeroCurrentDays() {
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 4)

        let result = SequenceAlignmentEngine.predict(
            currentDays: [],
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result == nil, "Should return nil with 0 current days")
    }

    @Test("Returns nil with fewer than 4 historical weeks")
    func testTooFewHistoryWeeks() {
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 3)

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result == nil, "Should return nil with < 4 historical weeks")
    }

    // MARK: - Prediction with repeated pattern

    @Test("Known repeated pattern produces matching prediction")
    func testRepeatedPatternPrediction() {
        // All history weeks have bedtime=23, wake=7
        let bedtime = 23.0
        let wake = 7.0
        let history = makeRepeatingHistory(bedtime: bedtime, wake: wake, weekCount: 6)

        // Current partial week: 3 days of the same pattern
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: bedtime, wake: wake)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil, "Should produce a prediction with sufficient data")
        guard let result else { return }

        // Predicted bedtime should be close to 23.0
        let bedDiff = abs(result.prediction.predictedBedtime - bedtime)
        #expect(bedDiff < 1.0, "Predicted bedtime \(result.prediction.predictedBedtime) should be near \(bedtime)")

        // Predicted wake should be close to 7.0
        let wakeDiff = abs(result.prediction.predictedWake - wake)
        #expect(wakeDiff < 1.0, "Predicted wake \(result.prediction.predictedWake) should be near \(wake)")

        // Duration should be close to 8 hours
        #expect(abs(result.prediction.predictedDuration - 8.0) < 1.0,
                "Duration \(result.prediction.predictedDuration) should be near 8h")
    }

    // MARK: - Engine type

    @Test("Returns .sequenceAlignment engine type")
    func testEngineType() {
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 5)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        #expect(result?.output.engine == .sequenceAlignment,
                "Engine should be .sequenceAlignment")
    }

    // MARK: - Confidence bounds

    @Test("Confidence is in [0, 1]")
    func testConfidenceBounds() {
        let history = makeRepeatingHistory(bedtime: 22, wake: 6, weekCount: 5)
        let currentDays = (0..<2).map {
            makeTimingNucleotide(day: $0, bedtime: 22, wake: 6)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }
        #expect(result.prediction.confidence >= 0.0, "Confidence should be >= 0")
        #expect(result.prediction.confidence <= 1.0, "Confidence should be <= 1")
    }

    @Test("High similarity yields high confidence")
    func testHighSimilarityHighConfidence() {
        // Identical pattern everywhere → very low DTW distance → high similarity
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 6)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }
        #expect(result.prediction.confidence > 0.5,
                "Identical pattern should yield good confidence, got \(result.prediction.confidence)")
    }

    // MARK: - Alignments

    @Test("Partial 3-day sequence finds top-5 similar weeks")
    func testTop5Alignments() {
        // 8 historical weeks — should return at most 5
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 8)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }

        #expect(result.alignments.count == 5,
                "Should return top 5 alignments, got \(result.alignments.count)")

        // Alignments should be sorted by DTW score (ascending)
        for i in 1..<result.alignments.count {
            #expect(result.alignments[i].dtwScore >= result.alignments[i - 1].dtwScore,
                    "Alignments should be sorted by ascending DTW score")
        }
    }

    @Test("Fewer than 5 history weeks returns all alignments")
    func testFewerThan5Weeks() {
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 4)
        let currentDays = (0..<2).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        #expect(result?.alignments.count == 4,
                "Should return all 4 alignments when < 5 weeks")
    }

    // MARK: - Predicted hours in range

    @Test("Predicted hours are in [0, 24)")
    func testPredictedHoursRange() {
        let history = makeRepeatingHistory(bedtime: 23.5, wake: 6.5, weekCount: 5)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23.5, wake: 6.5)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }

        #expect(result.prediction.predictedBedtime >= 0 && result.prediction.predictedBedtime < 24,
                "Bedtime \(result.prediction.predictedBedtime) should be in [0, 24)")
        #expect(result.prediction.predictedWake >= 0 && result.prediction.predictedWake < 24,
                "Wake \(result.prediction.predictedWake) should be in [0, 24)")
        #expect(result.output.predictedBedtimeHour >= 0 && result.output.predictedBedtimeHour < 24,
                "Output bedtime should be in [0, 24)")
        #expect(result.output.predictedWakeHour >= 0 && result.output.predictedWakeHour < 24,
                "Output wake should be in [0, 24)")
    }

    // MARK: - Week indices tracking

    @Test("basedOnWeekIndices contains valid indices")
    func testWeekIndicesValid() {
        let history = makeRepeatingHistory(bedtime: 22, wake: 6, weekCount: 6)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 22, wake: 6)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }

        for idx in result.prediction.basedOnWeekIndices {
            #expect(idx >= 0 && idx < history.count,
                    "Week index \(idx) should be valid for history of size \(history.count)")
        }
    }

    // MARK: - Similarity metric

    @Test("Similarity equals 1/(1+dtwScore)")
    func testSimilarityFormula() {
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 5)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }

        for alignment in result.alignments {
            let expected = 1.0 / (1.0 + alignment.dtwScore)
            #expect(abs(alignment.similarity - expected) < 1e-10,
                    "Similarity should be 1/(1+dtwScore)")
        }
    }

    // MARK: - Mixed history: similar weeks rank higher

    @Test("Similar weeks rank higher than dissimilar ones")
    func testSimilarWeeksRankHigher() {
        // Build a mix: 3 dissimilar weeks + 4 similar weeks
        let dissimilar = (0..<3).map { w in
            makeTimingWeek(startDay: w * 7, bedtime: 2, wake: 14) // very different pattern
        }
        let similar = (0..<4).map { w in
            makeTimingWeek(startDay: 21 + w * 7, bedtime: 23, wake: 7)
        }
        let history = dissimilar + similar

        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil)
        guard let result else { return }

        // Top alignments should primarily be from the similar weeks (indices 3-6)
        let topIndices = Set(result.alignments.prefix(4).map(\.weekIndex))
        let similarIndices = Set(3..<7)
        let overlap = topIndices.intersection(similarIndices)

        #expect(overlap.count >= 3,
                "At least 3 of top 4 should be from similar weeks, got \(overlap.count)")
    }

    // MARK: - Exactly 2 current days (boundary)

    @Test("Exactly 2 current days produces valid prediction")
    func testExactly2CurrentDays() {
        let history = makeRepeatingHistory(bedtime: 22.5, wake: 6.5, weekCount: 4)
        let currentDays = (0..<2).map {
            makeTimingNucleotide(day: $0, bedtime: 22.5, wake: 6.5)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil, "Exactly 2 days should be sufficient")
    }

    // MARK: - Exactly 4 history weeks (boundary)

    @Test("Exactly 4 historical weeks produces valid prediction")
    func testExactly4HistoryWeeks() {
        let history = makeRepeatingHistory(bedtime: 23, wake: 7, weekCount: 4)
        let currentDays = (0..<3).map {
            makeTimingNucleotide(day: $0, bedtime: 23, wake: 7)
        }

        let result = SequenceAlignmentEngine.predict(
            currentDays: currentDays,
            history: history,
            weights: nil,
            targetDate: Date()
        )

        #expect(result != nil, "Exactly 4 historical weeks should be sufficient")
    }
}
