import Testing
import Foundation
@testable import SpiralKit

@Suite("DTWEngine")
struct DTWEngineTests {

    // MARK: - Helpers

    /// Create a DayNucleotide with explicit features.
    private func makeNucleotide(day: Int, features: [Double]) -> DayNucleotide {
        DayNucleotide(day: day, features: features)
    }

    /// Create a week of nucleotides with constant features.
    private func makeConstantWeek(startDay: Int, value: Double) -> WeekSequence {
        let nucs = (0..<7).map { i in
            makeNucleotide(day: startDay + i, features: Array(repeating: value, count: 16))
        }
        return WeekSequence(startDay: startDay, nucleotides: nucs)
    }

    /// Create a week of nucleotides with varying features (each day gets feature[0] = Double(dayOffset) / 7).
    private func makeRampWeek(startDay: Int) -> WeekSequence {
        let nucs = (0..<7).map { i in
            var features = Array(repeating: 0.5, count: 16)
            features[0] = Double(i) / 7.0
            return makeNucleotide(day: startDay + i, features: features)
        }
        return WeekSequence(startDay: startDay, nucleotides: nucs)
    }

    /// Create a week where day i has feature[0] = values[i], rest 0.5.
    private func makeWeek(startDay: Int, feature0Values: [Double]) -> WeekSequence {
        precondition(feature0Values.count == 7)
        let nucs = (0..<7).map { i in
            var features = Array(repeating: 0.5, count: 16)
            features[0] = feature0Values[i]
            return makeNucleotide(day: startDay + i, features: features)
        }
        return WeekSequence(startDay: startDay, nucleotides: nucs)
    }

    // MARK: - Identical sequences

    @Test("Identical sequences have distance 0")
    func testIdenticalDistance() {
        let week = makeConstantWeek(startDay: 0, value: 0.5)
        let result = DTWEngine.distance(week, week)
        #expect(result.distance < 1e-10, "Distance between identical sequences should be 0, got \(result.distance)")
    }

    @Test("Identical ramp sequences have distance 0")
    func testIdenticalRampDistance() {
        let a = makeRampWeek(startDay: 0)
        let b = makeRampWeek(startDay: 7)
        let result = DTWEngine.distance(a, b)
        #expect(result.distance < 1e-10)
    }

    // MARK: - Non-identical sequences

    @Test("Different sequences have distance > 0")
    func testDifferentDistance() {
        let a = makeConstantWeek(startDay: 0, value: 0.0)
        let b = makeConstantWeek(startDay: 7, value: 1.0)
        let result = DTWEngine.distance(a, b)
        #expect(result.distance > 0, "Different sequences should have positive distance")
    }

    @Test("Reversed sequences have distance > 0")
    func testReversedDistance() {
        let values = [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]
        let reversed = values.reversed().map { $0 }
        let a = makeWeek(startDay: 0, feature0Values: values)
        let b = makeWeek(startDay: 7, feature0Values: reversed)
        let result = DTWEngine.distance(a, b)
        #expect(result.distance > 0, "Reversed sequences should have positive distance")
    }

    // MARK: - Symmetry

    @Test("DTW is symmetric: dtw(a,b) == dtw(b,a)")
    func testSymmetry() {
        let a = makeWeek(startDay: 0, feature0Values: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 0.5])
        let b = makeWeek(startDay: 7, feature0Values: [1.0, 0.8, 0.6, 0.4, 0.2, 0.0, 0.5])
        let ab = DTWEngine.distance(a, b)
        let ba = DTWEngine.distance(b, a)
        #expect(abs(ab.distance - ba.distance) < 1e-10, "DTW should be symmetric")
    }

    // MARK: - Weights

    @Test("Higher weight on differing feature increases distance")
    func testWeightsAffectDistance() {
        // Two weeks that differ only in feature 0
        let a = makeWeek(startDay: 0, feature0Values: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        let b = makeWeek(startDay: 7, feature0Values: [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

        let uniformWeights = Array(repeating: 1.0, count: 16)
        var heavyWeights = Array(repeating: 1.0, count: 16)
        heavyWeights[0] = 10.0  // weight feature 0 heavily

        let uniform = DTWEngine.distance(a, b, weights: uniformWeights)
        let heavy = DTWEngine.distance(a, b, weights: heavyWeights)

        #expect(heavy.distance > uniform.distance,
                "Higher weight on differing feature should increase distance: heavy=\(heavy.distance), uniform=\(uniform.distance)")
    }

    @Test("Zero weight on differing feature eliminates its contribution")
    func testZeroWeight() {
        // Differ only in feature 0, but weight it at 0
        let a = makeWeek(startDay: 0, feature0Values: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        let b = makeWeek(startDay: 7, feature0Values: [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

        var weights = Array(repeating: 1.0, count: 16)
        weights[0] = 0.0  // ignore the only differing feature

        let result = DTWEngine.distance(a, b, weights: weights)
        #expect(result.distance < 1e-10,
                "Zero weight on only differing feature should make distance 0, got \(result.distance)")
    }

    // MARK: - Path validity

    @Test("Path starts at (0,0) and ends at (n-1, m-1)")
    func testPathEndpoints() {
        let a = makeRampWeek(startDay: 0)
        let b = makeRampWeek(startDay: 7)
        let result = DTWEngine.distance(a, b)
        let path = result.path

        #expect(!path.isEmpty, "Path should not be empty")
        #expect(path.first?.0 == 0 && path.first?.1 == 0, "Path should start at (0, 0)")
        #expect(path.last?.0 == 6 && path.last?.1 == 6, "Path should end at (6, 6)")
    }

    @Test("Path indices are monotonically non-decreasing")
    func testPathMonotonicity() {
        let a = makeWeek(startDay: 0, feature0Values: [0.0, 0.5, 0.2, 0.8, 0.1, 0.9, 0.4])
        let b = makeWeek(startDay: 7, feature0Values: [0.9, 0.3, 0.7, 0.1, 0.6, 0.0, 0.5])
        let result = DTWEngine.distance(a, b)
        let path = result.path

        for i in 1..<path.count {
            #expect(path[i].0 >= path[i - 1].0, "Row indices should be non-decreasing")
            #expect(path[i].1 >= path[i - 1].1, "Column indices should be non-decreasing")
        }
    }

    @Test("Path steps increment by at most 1 in each dimension")
    func testPathStepSize() {
        let a = makeRampWeek(startDay: 0)
        let b = makeConstantWeek(startDay: 7, value: 0.3)
        let result = DTWEngine.distance(a, b)
        let path = result.path

        for i in 1..<path.count {
            let di = path[i].0 - path[i - 1].0
            let dj = path[i].1 - path[i - 1].1
            #expect(di >= 0 && di <= 1, "Row step should be 0 or 1")
            #expect(dj >= 0 && dj <= 1, "Col step should be 0 or 1")
            #expect(di + dj > 0, "Must advance at least one dimension per step")
        }
    }

    // MARK: - Partial DTW

    @Test("3-day partial against 7-day full works")
    func testPartialDTW() {
        let partial = (0..<3).map { i in
            makeNucleotide(day: i, features: Array(repeating: 0.5, count: 16))
        }
        let full = makeConstantWeek(startDay: 0, value: 0.5)
        let result = DTWEngine.partialDistance(partial: partial, full: full)

        #expect(result.distance < 1e-10, "Identical features should give distance 0")
        #expect(result.path.first?.0 == 0 && result.path.first?.1 == 0, "Path starts at (0, 0)")
        #expect(result.path.last?.0 == 2, "Path ends at row 2 (partial has 3 elements)")
        #expect(result.path.last?.1 == 6, "Path ends at col 6 (full has 7 elements)")
    }

    @Test("1-day partial against full week works")
    func testSingleDayPartial() {
        let partial = [makeNucleotide(day: 0, features: Array(repeating: 0.3, count: 16))]
        let full = makeConstantWeek(startDay: 0, value: 0.3)
        let result = DTWEngine.partialDistance(partial: partial, full: full)

        #expect(result.distance < 1e-10)
        #expect(result.path.count == 7, "1 row x 7 cols means path length 7")
    }

    @Test("Partial DTW with different features has positive distance")
    func testPartialDTWDifferent() {
        let partial = (0..<3).map { i in
            makeNucleotide(day: i, features: Array(repeating: 0.0, count: 16))
        }
        let full = makeConstantWeek(startDay: 0, value: 1.0)
        let result = DTWEngine.partialDistance(partial: partial, full: full)

        #expect(result.distance > 0, "Different features should yield positive distance")
    }

    // MARK: - Triangle inequality (informational)

    @Test("DTW satisfies approximate triangle inequality property")
    func testTriangleInequality() {
        let a = makeWeek(startDay: 0, feature0Values: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6])
        let b = makeWeek(startDay: 7, feature0Values: [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])
        let c = makeWeek(startDay: 14, feature0Values: [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4])

        let dAB = DTWEngine.distance(a, b).distance
        let dBC = DTWEngine.distance(b, c).distance
        let dAC = DTWEngine.distance(a, c).distance

        // DTW does not guarantee triangle inequality, but for these simple sequences it typically holds
        // This test documents the property without being a strict requirement
        #expect(dAC <= dAB + dBC + 1e-10,
                "Triangle inequality: d(A,C)=\(dAC) <= d(A,B)+d(B,C)=\(dAB + dBC)")
    }
}
