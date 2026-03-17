import Foundation
import Testing
@testable import SpiralKit

@Suite("MutationClassifier Tests")
struct MutationClassifierTests {

    // MARK: - Helpers

    private func makeNucleotide(day: Int, base: Double = 0.5, overrides: [Int: Double] = [:]) -> DayNucleotide {
        var features = [Double](repeating: base, count: DayNucleotide.featureCount)
        for (idx, val) in overrides {
            features[idx] = val
        }
        return DayNucleotide(day: day, features: features)
    }

    private func makeWeek(startDay: Int, base: Double = 0.5, overrides: [Int: Double] = [:]) -> WeekSequence {
        let nucleotides = (0..<7).map { i in
            makeNucleotide(day: startDay + i, base: base, overrides: overrides)
        }
        return WeekSequence(startDay: startDay, nucleotides: nucleotides)
    }

    /// Build a motif manually for controlled testing.
    private func makeMotif(
        id: UUID = UUID(),
        name: String = "Test",
        centroid: [DayNucleotide],
        instanceCount: Int,
        instanceWeekIndices: [Int] = [],
        avgQuality: Double
    ) -> SleepMotif {
        SleepMotif(
            id: id,
            name: name,
            windowSize: 7,
            centroid: centroid,
            instanceCount: instanceCount,
            instanceWeekIndices: instanceWeekIndices,
            avgQuality: avgQuality
        )
    }

    // MARK: - Mutation Classification Tests

    @Test("Quality delta < 0.05 classified as silent")
    func silentMutation() {
        // Motif has avgQuality 0.5, week also has quality ~0.5 -> delta near 0
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(centroid: centroid, instanceCount: 4, avgQuality: 0.5)

        // Week with quality = 0.52 -> delta = 0.02 (silent)
        let week = makeWeek(startDay: 0, base: 0.5, overrides: [qualityIdx: 0.52])
        let mutations = MutationClassifier.classifyMutations(
            sequences: [week], motifs: [motif]
        )
        #expect(mutations.count == 1)
        #expect(mutations[0].classification == .silent,
                "Delta ~0.02 should be silent, got \(mutations[0].classification)")
        #expect(abs(mutations[0].qualityDelta) < 0.05)
    }

    @Test("Quality delta ~0.10 classified as missense")
    func missenseMutation() {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(centroid: centroid, instanceCount: 4, avgQuality: 0.5)

        // Week with quality = 0.60 -> delta = 0.10 (missense)
        let week = makeWeek(startDay: 0, base: 0.5, overrides: [qualityIdx: 0.60])
        let mutations = MutationClassifier.classifyMutations(
            sequences: [week], motifs: [motif]
        )
        #expect(mutations.count == 1)
        #expect(mutations[0].classification == .missense,
                "Delta ~0.10 should be missense, got \(mutations[0].classification)")
    }

    @Test("Quality delta ~0.20 classified as nonsense")
    func nonsenseMutation() {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(centroid: centroid, instanceCount: 4, avgQuality: 0.5)

        // Week with quality = 0.70 -> delta = 0.20 (nonsense)
        let week = makeWeek(startDay: 0, base: 0.5, overrides: [qualityIdx: 0.70])
        let mutations = MutationClassifier.classifyMutations(
            sequences: [week], motifs: [motif]
        )
        #expect(mutations.count == 1)
        #expect(mutations[0].classification == .nonsense,
                "Delta ~0.20 should be nonsense, got \(mutations[0].classification)")
    }

    @Test("No motifs returns empty mutations")
    func noMotifsEmptyMutations() {
        let week = makeWeek(startDay: 0, base: 0.5)
        let mutations = MutationClassifier.classifyMutations(sequences: [week], motifs: [])
        #expect(mutations.isEmpty)
    }

    // MARK: - Expression Rule Tests

    @Test("Expression rule detected when context feature splits quality")
    func expressionRuleDetected() {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let exerciseIdx = DayNucleotide.Feature.exercise.rawValue

        // Create a motif centroid
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(
            centroid: centroid,
            instanceCount: 6,
            instanceWeekIndices: Array(0..<6),
            avgQuality: 0.5
        )

        // Create 6 weeks: 3 with high exercise + high quality, 3 with low exercise + low quality
        var weeks: [WeekSequence] = []
        for i in 0..<3 {
            // High exercise, high quality
            weeks.append(makeWeek(
                startDay: i * 7, base: 0.5,
                overrides: [exerciseIdx: 0.9, qualityIdx: 0.8]
            ))
        }
        for i in 3..<6 {
            // Low exercise, low quality
            weeks.append(makeWeek(
                startDay: i * 7, base: 0.5,
                overrides: [exerciseIdx: 0.1, qualityIdx: 0.3]
            ))
        }

        let rules = MutationClassifier.discoverExpressionRules(
            sequences: weeks, motifs: [motif]
        )

        // Should find at least one rule involving exercise (index 9)
        let exerciseRules = rules.filter { $0.regulatorFeatureIndex == exerciseIdx }
        #expect(!exerciseRules.isEmpty,
                "Should detect exercise as a quality regulator")
        if let rule = exerciseRules.first {
            #expect(rule.qualityWith > rule.qualityWithout,
                    "High exercise should correlate with higher quality")
        }
    }

    @Test("No expression rules with fewer than 4 motif instances")
    func noRulesWithFewInstances() {
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(centroid: centroid, instanceCount: 2, avgQuality: 0.5)

        let weeks = (0..<2).map { i in makeWeek(startDay: i * 7, base: 0.5) }
        let rules = MutationClassifier.discoverExpressionRules(
            sequences: weeks, motifs: [motif]
        )
        #expect(rules.isEmpty, "Should not find rules with < 4 instances")
    }

    @Test("Dominant change index points to the most-deviated feature")
    func dominantChangeIndex() {
        let caffeineIdx = DayNucleotide.Feature.caffeine.rawValue
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(centroid: centroid, instanceCount: 4, avgQuality: 0.5)

        // Week where caffeine is very different from centroid (0.5 -> 1.0)
        let week = makeWeek(startDay: 0, base: 0.5, overrides: [caffeineIdx: 1.0])
        let mutations = MutationClassifier.classifyMutations(
            sequences: [week], motifs: [motif]
        )
        #expect(mutations.count == 1)
        #expect(mutations[0].dominantChangeIndex == caffeineIdx,
                "Dominant change should be caffeine (idx \(caffeineIdx)), got \(mutations[0].dominantChangeIndex)")
    }

    @Test("Each mutation has the correct motif ID")
    func mutationMotifID() {
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motifID = UUID()
        let motif = makeMotif(id: motifID, centroid: centroid, instanceCount: 4, avgQuality: 0.5)

        let week = makeWeek(startDay: 0, base: 0.5)
        let mutations = MutationClassifier.classifyMutations(
            sequences: [week], motifs: [motif]
        )
        #expect(mutations[0].motifID == motifID)
    }

    @Test("Expression rule has correct motif ID")
    func expressionRuleMotifID() {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let stressIdx = DayNucleotide.Feature.stress.rawValue
        let motifID = UUID()
        let centroid = (0..<7).map { makeNucleotide(day: $0, base: 0.5) }
        let motif = makeMotif(
            id: motifID,
            centroid: centroid,
            instanceCount: 6,
            instanceWeekIndices: Array(0..<6),
            avgQuality: 0.5
        )

        var weeks: [WeekSequence] = []
        for i in 0..<3 {
            weeks.append(makeWeek(startDay: i * 7, base: 0.5,
                                  overrides: [stressIdx: 0.9, qualityIdx: 0.3]))
        }
        for i in 3..<6 {
            weeks.append(makeWeek(startDay: i * 7, base: 0.5,
                                  overrides: [stressIdx: 0.1, qualityIdx: 0.8]))
        }

        let rules = MutationClassifier.discoverExpressionRules(
            sequences: weeks, motifs: [motif]
        )
        for rule in rules {
            #expect(rule.motifID == motifID)
        }
    }
}
