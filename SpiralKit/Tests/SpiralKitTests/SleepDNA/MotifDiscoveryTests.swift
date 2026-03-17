import Foundation
import Testing
@testable import SpiralKit

@Suite("MotifDiscovery Tests")
struct MotifDiscoveryTests {

    // MARK: - Helpers

    /// Create a DayNucleotide with all features set to a base value, with optional overrides.
    private func makeNucleotide(day: Int, base: Double = 0.5, overrides: [Int: Double] = [:]) -> DayNucleotide {
        var features = [Double](repeating: base, count: DayNucleotide.featureCount)
        for (idx, val) in overrides {
            features[idx] = val
        }
        return DayNucleotide(day: day, features: features)
    }

    /// Create a WeekSequence with 7 identical nucleotides at the given base value.
    private func makeWeek(startDay: Int, base: Double = 0.5, overrides: [Int: Double] = [:]) -> WeekSequence {
        let nucleotides = (0..<7).map { i in
            makeNucleotide(day: startDay + i, base: base, overrides: overrides)
        }
        return WeekSequence(startDay: startDay, nucleotides: nucleotides)
    }

    // MARK: - Tests

    @Test("4 identical weeks produce 1 motif with 4 instances")
    func fourIdenticalWeeks() {
        let weeks = (0..<4).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        #expect(motifs.count == 1, "Expected 1 motif, got \(motifs.count)")
        #expect(motifs[0].instanceCount == 4, "Expected 4 instances, got \(motifs[0].instanceCount)")
    }

    @Test("2 groups of 3 similar weeks produce 2 motifs")
    func twoGroupsOfThree() {
        // Group A: low base value
        let groupA = (0..<3).map { i in makeWeek(startDay: i * 7, base: 0.1) }
        // Group B: high base value
        let groupB = (0..<3).map { i in makeWeek(startDay: 21 + i * 7, base: 0.9) }
        let weeks = groupA + groupB
        let motifs = MotifDiscovery.discover(sequences: weeks, threshold: 12.0)
        #expect(motifs.count == 2, "Expected 2 motifs, got \(motifs.count)")
        // Each group should have 3 instances
        let counts = motifs.map(\.instanceCount).sorted()
        #expect(counts == [3, 3], "Expected [3, 3], got \(counts)")
    }

    @Test("Fewer than 4 sequences returns empty")
    func tooFewSequences() {
        let weeks = (0..<3).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        #expect(motifs.isEmpty, "Expected no motifs with < 4 sequences")
    }

    @Test("Motif names are non-empty strings")
    func motifNamesNonEmpty() {
        let weeks = (0..<5).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        for motif in motifs {
            #expect(!motif.name.isEmpty, "Motif name should not be empty")
        }
    }

    @Test("Instance count matches cluster sizes")
    func instanceCountMatchesClusterSize() {
        // 6 identical weeks — should form one cluster of 6
        let weeks = (0..<6).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        let totalInstances = motifs.reduce(0) { $0 + $1.instanceCount }
        // Total instances across all motifs should equal the number of weeks that were clustered
        // (singletons are dropped, so total may be less than 6 if some were singletons)
        #expect(totalInstances <= weeks.count)
        for motif in motifs {
            #expect(motif.instanceWeekIndices.count == motif.instanceCount)
        }
    }

    @Test("Motifs are sorted by instance count descending")
    func sortedByInstanceCount() {
        // Create two distinct groups: a larger group and a smaller group
        let groupA = (0..<5).map { i in makeWeek(startDay: i * 7, base: 0.2) }
        let groupB = (0..<3).map { i in makeWeek(startDay: 35 + i * 7, base: 0.8) }
        let weeks = groupA + groupB
        let motifs = MotifDiscovery.discover(sequences: weeks, threshold: 12.0)
        for i in 0..<(motifs.count - 1) {
            #expect(motifs[i].instanceCount >= motifs[i + 1].instanceCount,
                    "Motifs should be sorted by instance count descending")
        }
    }

    @Test("Window size is always 7")
    func windowSizeAlways7() {
        let weeks = (0..<5).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        for motif in motifs {
            #expect(motif.windowSize == 7, "Window size should always be 7")
        }
    }

    @Test("Centroid has 7 nucleotides")
    func centroidLength() {
        let weeks = (0..<5).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let motifs = MotifDiscovery.discover(sequences: weeks)
        for motif in motifs {
            #expect(motif.centroid.count == 7, "Centroid should have 7 nucleotides")
        }
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let motifs = MotifDiscovery.discover(sequences: [])
        #expect(motifs.isEmpty)
    }
}
