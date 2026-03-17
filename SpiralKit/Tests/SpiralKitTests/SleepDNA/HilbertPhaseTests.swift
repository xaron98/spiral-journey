import Testing
import Foundation
@testable import SpiralKit

@Suite("HilbertPhaseAnalyzer")
struct HilbertPhaseTests {

    // MARK: - Helpers

    /// Create a DayNucleotide with explicit feature values.
    private func makeNucleotide(day: Int, features: [Double]) -> DayNucleotide {
        DayNucleotide(day: day, features: features)
    }

    /// Create nucleotides where strand-1 feature `s1` and strand-2 feature `s2`
    /// follow given waveforms, all other features are 0.5 (constant).
    private func makeNucleotides(
        count: Int,
        s1Index: Int = 0,
        s1Values: [Double],
        s2Index: Int = 8,
        s2Values: [Double]
    ) -> [DayNucleotide] {
        (0..<count).map { day in
            var features = [Double](repeating: 0.5, count: 16)
            features[s1Index] = s1Values[day]
            features[s2Index] = s2Values[day]
            return makeNucleotide(day: day, features: features)
        }
    }

    /// Generate a sine wave of given length and phase offset.
    private func sineWave(count: Int, phaseOffset: Double = 0, frequency: Double = 1) -> [Double] {
        (0..<count).map { i in
            sin(2 * Double.pi * frequency * Double(i) / Double(count) + phaseOffset)
        }
    }

    // MARK: - Tests

    @Test("In-phase signals have high PLV")
    func testInPhaseHighPLV() {
        let count = 14
        let wave = sineWave(count: count, frequency: 2)
        let nucs = makeNucleotides(count: count, s1Values: wave, s2Values: wave)

        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        // The pair (0, 8) should have high PLV since both signals are identical
        let pair = results.first { $0.sleepFeatureIndex == 0 && $0.contextFeatureIndex == 8 }
        #expect(pair != nil, "In-phase pair should be present in results")
        if let pair {
            #expect(pair.plv > 0.9, "PLV for identical signals should be near 1.0, got \(pair.plv)")
        }
    }

    @Test("Random signals have low PLV")
    func testRandomLowPLV() {
        // Use deterministic "random" sequences that are unrelated
        let count = 14
        // Two unrelated sequences with different patterns
        let seq1 = (0..<count).map { i in sin(2 * Double.pi * 3.0 * Double(i) / Double(count)) }
        let seq2 = (0..<count).map { i in cos(2 * Double.pi * 7.0 * Double(i) / Double(count) + 1.3) }

        let nucs = makeNucleotides(count: count, s1Values: seq1, s2Values: seq2)
        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        // The pair (0, 8) should either be absent (PLV <= 0.3) or have low PLV
        let pair = results.first { $0.sleepFeatureIndex == 0 && $0.contextFeatureIndex == 8 }
        if let pair {
            // If it made it past the filter, it should still be relatively low
            #expect(pair.plv < 0.5, "Unrelated signals should have low PLV, got \(pair.plv)")
        }
        // If pair is nil, PLV was below threshold — that's the expected outcome
    }

    @Test("Anti-phase signals have high PLV with pi phase diff")
    func testAntiPhaseSignals() {
        let count = 14
        let wave1 = sineWave(count: count, frequency: 2)
        let wave2 = sineWave(count: count, phaseOffset: Double.pi, frequency: 2)

        let nucs = makeNucleotides(count: count, s1Values: wave1, s2Values: wave2)
        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        let pair = results.first { $0.sleepFeatureIndex == 0 && $0.contextFeatureIndex == 8 }
        #expect(pair != nil, "Anti-phase pair should be present")
        if let pair {
            #expect(pair.plv > 0.9, "PLV for anti-phase signals should be near 1.0, got \(pair.plv)")
            // meanPhaseDiff should be near +pi or -pi
            let absDiff = abs(pair.meanPhaseDiff)
            #expect(absDiff > 2.5, "Mean phase diff for anti-phase should be near pi, got \(absDiff)")
        }
    }

    @Test("Short input returns empty")
    func testShortInputEmpty() {
        // Fewer than 4 nucleotides should return empty
        let nucs = (0..<3).map { day in
            DayNucleotide(day: day, features: [Double](repeating: 0.5, count: 16))
        }
        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: 14)
        #expect(results.isEmpty, "Should return empty for fewer than 4 nucleotides")
    }

    @Test("Only significant pairs returned")
    func testOnlySignificantPairs() {
        let count = 14
        let wave = sineWave(count: count, frequency: 2)
        let nucs = makeNucleotides(count: count, s1Values: wave, s2Values: wave)

        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        for pair in results {
            #expect(pair.plv > 0.3, "All returned pairs should have PLV > 0.3, got \(pair.plv)")
        }
    }

    @Test("Results are sorted by PLV descending")
    func testSortedByPLVDescending() {
        let count = 14
        let wave = sineWave(count: count, frequency: 2)
        let nucs = makeNucleotides(count: count, s1Values: wave, s2Values: wave)

        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        guard results.count >= 2 else { return }
        for i in 0..<(results.count - 1) {
            #expect(results[i].plv >= results[i + 1].plv,
                    "Results should be sorted by PLV descending")
        }
    }

    @Test("Feature indices are correct ranges")
    func testFeatureIndexRanges() {
        let count = 14
        let wave = sineWave(count: count, frequency: 2)
        let nucs = makeNucleotides(count: count, s1Values: wave, s2Values: wave)

        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)

        for pair in results {
            #expect(pair.sleepFeatureIndex >= 0 && pair.sleepFeatureIndex < 8,
                    "Sleep feature index should be 0-7, got \(pair.sleepFeatureIndex)")
            #expect(pair.contextFeatureIndex >= 8 && pair.contextFeatureIndex < 16,
                    "Context feature index should be 8-15, got \(pair.contextFeatureIndex)")
            #expect(pair.lagDays == 0, "Lag days should be 0 for now")
        }
    }

    @Test("Constant signal pairs are excluded")
    func testConstantSignalExcluded() {
        // All features are constant 0.5 — should produce no phase-locked pairs
        let count = 14
        let nucs = (0..<count).map { day in
            DayNucleotide(day: day, features: [Double](repeating: 0.5, count: 16))
        }
        let results = HilbertPhaseAnalyzer.analyze(nucleotides: nucs, windowSize: count)
        #expect(results.isEmpty, "Constant signals should produce no synchrony pairs")
    }

    @Test("PLV computation for known phases")
    func testPLVComputation() {
        // Identical phase arrays → PLV = 1.0, meanPhaseDiff = 0
        let phases = [0.0, 0.5, 1.0, 1.5, 2.0]
        let (plv, diff) = HilbertPhaseAnalyzer.computePLV(phase1: phases, phase2: phases)
        #expect(abs(plv - 1.0) < 1e-10, "Identical phases should give PLV = 1.0")
        #expect(abs(diff) < 1e-10, "Identical phases should give zero mean diff")
    }
}
