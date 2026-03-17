import Testing
import Foundation
@testable import SpiralKit

@Suite("SleepBLOSUM")
struct SleepBLOSUMTests {

    // MARK: - Helpers

    /// Create a DayNucleotide with explicit features.
    private func makeNucleotide(day: Int, features: [Double]) -> DayNucleotide {
        DayNucleotide(day: day, features: features)
    }

    /// Create nucleotides with random-ish but deterministic features.
    private func makeRandomNucleotides(count: Int, seed: Int = 42) -> [DayNucleotide] {
        (0..<count).map { i in
            var features = [Double](repeating: 0, count: 16)
            for f in 0..<16 {
                // Simple deterministic pseudo-random using a hash-like mix
                let raw = (i * 7 + f * 13 + seed) % 100
                features[f] = Double(raw) / 100.0
            }
            return makeNucleotide(day: i, features: features)
        }
    }

    // MARK: - Initial weights

    @Test("Initial weights are all 1.0 with count 16")
    func testInitialWeights() {
        let blosum = SleepBLOSUM.initial
        #expect(blosum.weights.count == 16)
        for w in blosum.weights {
            #expect(w == 1.0)
        }
    }

    // MARK: - Short input

    @Test("Short input (<14) returns .initial")
    func testShortInput() {
        let nucs13 = makeRandomNucleotides(count: 13)
        let result = SleepBLOSUM.learn(from: nucs13)
        #expect(result.weights == SleepBLOSUM.initial.weights)

        let nucs1 = makeRandomNucleotides(count: 1)
        let result1 = SleepBLOSUM.learn(from: nucs1)
        #expect(result1.weights == SleepBLOSUM.initial.weights)

        let result0 = SleepBLOSUM.learn(from: [])
        #expect(result0.weights == SleepBLOSUM.initial.weights)
    }

    @Test("Exactly 14 nucleotides does NOT return .initial")
    func testExactly14() {
        let nucs = makeRandomNucleotides(count: 14)
        let result = SleepBLOSUM.learn(from: nucs)
        // Should have learned something (at least one weight differs from 1.0)
        #expect(result.weights.count == 16)
        let allOnes = result.weights.allSatisfy { $0 == 1.0 }
        #expect(!allOnes, "14 nucleotides should learn non-trivial weights")
    }

    // MARK: - All weights positive

    @Test("All weights are positive after learning")
    func testAllWeightsPositive() {
        let nucs = makeRandomNucleotides(count: 30)
        let result = SleepBLOSUM.learn(from: nucs)
        for (i, w) in result.weights.enumerated() {
            #expect(w > 0, "Weight \(i) should be positive, got \(w)")
        }
    }

    // MARK: - Max weight normalization

    @Test("Max weight after normalization <= 3.0")
    func testMaxWeightCap() {
        let nucs = makeRandomNucleotides(count: 50)
        let result = SleepBLOSUM.learn(from: nucs)
        let maxW = result.weights.max() ?? 0
        #expect(maxW <= 3.0 + 1e-10, "Max weight should be <= 3.0, got \(maxW)")
    }

    @Test("Max weight is approximately 3.0 (normalization fills range)")
    func testMaxWeightApprox3() {
        let nucs = makeRandomNucleotides(count: 50)
        let result = SleepBLOSUM.learn(from: nucs)
        let maxW = result.weights.max() ?? 0
        // The normalization scales so max == 3.0
        #expect(abs(maxW - 3.0) < 1e-10, "Max weight should be exactly 3.0, got \(maxW)")
    }

    // MARK: - Predictive feature gets highest weight

    @Test("Feature that perfectly predicts next-day quality gets highest weight")
    func testPredictiveFeatureHighest() {
        // Create nucleotides where feature 0 perfectly predicts next-day quality (feature 15)
        // Feature 0 on day i = quality on day i+1
        let count = 30
        var nucleotides: [DayNucleotide] = []

        for i in 0..<count {
            var features = [Double](repeating: 0.5, count: 16)
            // Feature 0: cycles through values
            let predictiveValue = Double(i % 5) / 4.0
            features[0] = predictiveValue
            // Quality (feature 15): matches feature 0 of PREVIOUS day
            if i > 0 {
                features[15] = Double((i - 1) % 5) / 4.0
            } else {
                features[15] = 0.5
            }
            nucleotides.append(makeNucleotide(day: i, features: features))
        }

        let result = SleepBLOSUM.learn(from: nucleotides)

        // Feature 0 should have the highest (or near-highest) weight
        let feature0Weight = result.weights[0]
        let maxWeight = result.weights.max() ?? 0

        #expect(feature0Weight == maxWeight,
                "Predictive feature 0 should get max weight. f0=\(feature0Weight), max=\(maxWeight)")
    }

    // MARK: - Constant feature gets low weight

    @Test("Constant feature gets minimum weight")
    func testConstantFeatureLowWeight() {
        // Feature 3 is constant (0.5 always), so MI with anything = 0
        let count = 30
        var nucleotides: [DayNucleotide] = []

        for i in 0..<count {
            var features = [Double](repeating: 0.5, count: 16)
            // Vary some features
            features[0] = Double(i % 5) / 4.0
            features[1] = Double(i % 3) / 2.0
            // Feature 3 stays constant
            features[3] = 0.5
            // Quality varies
            features[15] = Double(i % 4) / 3.0
            nucleotides.append(makeNucleotide(day: i, features: features))
        }

        let result = SleepBLOSUM.learn(from: nucleotides)
        let minWeight = result.weights.min() ?? 0

        // Constant feature 3 should get the minimum weight (MI = 0 → weight = max(0.1, 0) = 0.1 → scaled)
        #expect(result.weights[3] <= minWeight + 1e-10,
                "Constant feature should get minimum weight, got \(result.weights[3])")
    }

    // MARK: - Weight count

    @Test("Learned weights always have 16 elements")
    func testWeightCount() {
        let nucs = makeRandomNucleotides(count: 20)
        let result = SleepBLOSUM.learn(from: nucs)
        #expect(result.weights.count == 16)
    }

    // MARK: - Codable

    @Test("SleepBLOSUM round-trips through JSON encoding")
    func testCodable() throws {
        let blosum = SleepBLOSUM(weights: (0..<16).map { Double($0) * 0.2 + 0.1 })
        let data = try JSONEncoder().encode(blosum)
        let decoded = try JSONDecoder().decode(SleepBLOSUM.self, from: data)
        #expect(decoded.weights == blosum.weights)
    }

    // MARK: - Integration with DTWEngine

    @Test("Learned weights can be used with DTWEngine")
    func testIntegrationWithDTW() {
        let nucs = makeRandomNucleotides(count: 20)
        let blosum = SleepBLOSUM.learn(from: nucs)

        let weekA = WeekSequence(startDay: 0, nucleotides: Array(nucs[0..<7]))
        let weekB = WeekSequence(startDay: 7, nucleotides: Array(nucs[7..<14]))

        let uniformResult = DTWEngine.distance(weekA, weekB)
        let learnedResult = DTWEngine.distance(weekA, weekB, weights: blosum.weights)

        // Both should produce valid distances
        #expect(uniformResult.distance >= 0)
        #expect(learnedResult.distance >= 0)
        // Learned weights generally differ from uniform
        // (not strictly guaranteed, but very likely with varied data)
    }
}
