import Foundation

/// Classification of how much a week's sleep quality deviates from its motif's expected quality.
public enum MutationType: String, Codable, Sendable {
    /// Quality delta < 0.05 — negligible deviation.
    case silent
    /// Quality delta 0.05 - 0.15 — moderate deviation.
    case missense
    /// Quality delta > 0.15 — large deviation.
    case nonsense
}

/// A single week's deviation from its closest motif's expected sleep quality.
public struct SleepMutation: Identifiable, Codable, Sendable {
    public let id: UUID
    /// The motif this week was assigned to.
    public let motifID: UUID
    /// The starting day of the week sequence.
    public let day: Int
    /// Silent / missense / nonsense classification.
    public let classification: MutationType
    /// Actual week quality minus motif's average quality (signed).
    public let qualityDelta: Double
    /// Feature index that changed the most relative to the motif centroid.
    public let dominantChangeIndex: Int
}

/// A rule describing how a strand-2 (context) feature modulates a motif's sleep quality.
public struct ExpressionRule: Identifiable, Codable, Sendable {
    public let id: UUID
    /// The motif this rule applies to.
    public let motifID: UUID
    /// Strand-2 feature index (8-15) that acts as a regulator.
    public let regulatorFeatureIndex: Int
    /// Median-split threshold for the regulator feature.
    public let regulatorThreshold: Double
    /// Average quality of instances where the regulator is above the threshold.
    public let qualityWith: Double
    /// Average quality of instances where the regulator is at or below the threshold.
    public let qualityWithout: Double
}

/// Classifies week-to-motif mutations and discovers expression rules.
public enum MutationClassifier {

    /// Minimum number of motif instances required to compute expression rules.
    private static let minimumInstancesForRules = 4

    /// Quality difference threshold for expression rule significance.
    private static let ruleSignificanceThreshold = 0.05

    // MARK: - Mutations

    /// Classify each week sequence as a mutation relative to its closest motif.
    ///
    /// - Parameters:
    ///   - sequences: All week sequences from the user's history.
    ///   - motifs: Discovered motifs from `MotifDiscovery`.
    ///   - weights: Optional BLOSUM weights for DTW distance. Defaults to uniform 1.0.
    /// - Returns: One `SleepMutation` per input sequence.
    public static func classifyMutations(
        sequences: [WeekSequence],
        motifs: [SleepMotif],
        weights: [Double]? = nil
    ) -> [SleepMutation] {
        guard !motifs.isEmpty else { return [] }
        let w = weights ?? Array(repeating: 1.0, count: DayNucleotide.featureCount)

        return sequences.map { seq in
            let (closestMotif, _) = findClosestMotif(sequence: seq, motifs: motifs, weights: w)
            let weekQuality = averageQuality(of: seq)
            let delta = weekQuality - closestMotif.avgQuality
            let classification = classify(delta: delta, centroid: closestMotif.centroid)
            let dominantIdx = findDominantChange(sequence: seq, centroid: closestMotif.centroid)

            return SleepMutation(
                id: UUID(),
                motifID: closestMotif.id,
                day: seq.startDay,
                classification: classification,
                qualityDelta: delta,
                dominantChangeIndex: dominantIdx
            )
        }
    }

    // MARK: - Expression Rules

    /// Discover expression rules that link strand-2 context features to quality outcomes.
    ///
    /// For each motif with sufficient instances, splits instances by the median of each
    /// strand-2 feature and checks whether quality differs significantly between groups.
    ///
    /// - Parameters:
    ///   - sequences: All week sequences.
    ///   - motifs: Discovered motifs.
    ///   - weights: Optional BLOSUM weights for DTW. Defaults to uniform 1.0.
    /// - Returns: Expression rules where a context feature significantly modulates quality.
    public static func discoverExpressionRules(
        sequences: [WeekSequence],
        motifs: [SleepMotif],
        weights: [Double]? = nil
    ) -> [ExpressionRule] {
        guard !motifs.isEmpty else { return [] }
        let w = weights ?? Array(repeating: 1.0, count: DayNucleotide.featureCount)

        // Assign each sequence to its closest motif
        var motifMembers: [UUID: [WeekSequence]] = [:]
        for seq in sequences {
            let (closest, _) = findClosestMotif(sequence: seq, motifs: motifs, weights: w)
            motifMembers[closest.id, default: []].append(seq)
        }

        var rules: [ExpressionRule] = []

        for motif in motifs {
            let members = motifMembers[motif.id] ?? []
            guard members.count >= minimumInstancesForRules else { continue }

            // For each strand-2 feature (indices 8-15)
            for featureIdx in 8..<16 {
                // Compute the mean of this feature across each member week
                let featureValues = members.map { seq -> Double in
                    let vals = seq.nucleotides.map { $0.features[featureIdx] }
                    return vals.reduce(0, +) / Double(vals.count)
                }

                // Find median
                let sorted = featureValues.sorted()
                let median: Double
                if sorted.count % 2 == 0 {
                    median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
                } else {
                    median = sorted[sorted.count / 2]
                }

                // Split into high (> median) and low (<= median) groups
                var highQualities: [Double] = []
                var lowQualities: [Double] = []
                for (i, val) in featureValues.enumerated() {
                    let q = averageQuality(of: members[i])
                    if val > median {
                        highQualities.append(q)
                    } else {
                        lowQualities.append(q)
                    }
                }

                // Need both groups non-empty
                guard !highQualities.isEmpty, !lowQualities.isEmpty else { continue }

                let avgHigh = highQualities.reduce(0, +) / Double(highQualities.count)
                let avgLow = lowQualities.reduce(0, +) / Double(lowQualities.count)

                if abs(avgHigh - avgLow) > ruleSignificanceThreshold {
                    rules.append(ExpressionRule(
                        id: UUID(),
                        motifID: motif.id,
                        regulatorFeatureIndex: featureIdx,
                        regulatorThreshold: median,
                        qualityWith: avgHigh,
                        qualityWithout: avgLow
                    ))
                }
            }
        }

        return rules
    }

    // MARK: - Helpers

    /// Find the motif closest to the given sequence by DTW distance to its centroid.
    private static func findClosestMotif(
        sequence: WeekSequence,
        motifs: [SleepMotif],
        weights: [Double]
    ) -> (SleepMotif, Double) {
        var bestMotif = motifs[0]
        var bestDist = Double.infinity

        for motif in motifs {
            let centroidSeq = WeekSequence(
                startDay: motif.centroid.first?.day ?? 0,
                nucleotides: motif.centroid
            )
            let d = DTWEngine.distance(sequence, centroidSeq, weights: weights).distance
            if d < bestDist {
                bestDist = d
                bestMotif = motif
            }
        }

        return (bestMotif, bestDist)
    }

    /// Classify a quality delta into a mutation type using adaptive thresholds.
    ///
    /// Thresholds vary based on the motif's dominant time of day, derived from
    /// the centroid's bedtime features:
    /// - **Night hours (23:00-07:00):** stricter thresholds (0.03 / 0.10)
    /// - **Day hours (07:00-23:00):** relaxed thresholds (0.07 / 0.20)
    private static func classify(delta: Double, centroid: [DayNucleotide]) -> MutationType {
        let isNightDominant = Self.isNightDominant(centroid: centroid)
        let silentThreshold: Double = isNightDominant ? 0.03 : 0.07
        let missenseThreshold: Double = isNightDominant ? 0.10 : 0.20

        let absDelta = abs(delta)
        if absDelta < silentThreshold {
            return .silent
        } else if absDelta <= missenseThreshold {
            return .missense
        } else {
            return .nonsense
        }
    }

    /// Determine whether the motif's centroid represents a night-dominant pattern.
    ///
    /// Decodes bedtime from the centroid's mean bedtimeSin and bedtimeCos features
    /// using `atan2`, then checks if the bedtime falls in the night window (23:00-07:00).
    private static func isNightDominant(centroid: [DayNucleotide]) -> Bool {
        guard !centroid.isEmpty else { return true }

        let sinIdx = DayNucleotide.Feature.bedtimeSin.rawValue
        let cosIdx = DayNucleotide.Feature.bedtimeCos.rawValue

        // Average bedtime sin/cos across the centroid's days
        let meanSin = centroid.map { $0.features[sinIdx] }.reduce(0, +) / Double(centroid.count)
        let meanCos = centroid.map { $0.features[cosIdx] }.reduce(0, +) / Double(centroid.count)

        // Decode hour from circular encoding: bedRad = 2*pi*hour/24
        var radians = atan2(meanSin, meanCos)
        if radians < 0 { radians += 2 * Double.pi }
        let hour = radians * 24.0 / (2 * Double.pi)

        // Night window: 23:00 to 07:00 (wraps around midnight)
        return hour >= 23.0 || hour < 7.0
    }

    /// Average sleep quality across all nucleotides in a week sequence.
    private static func averageQuality(of seq: WeekSequence) -> Double {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        let qualities = seq.nucleotides.map { $0.features[qualityIdx] }
        guard !qualities.isEmpty else { return 0 }
        return qualities.reduce(0, +) / Double(qualities.count)
    }

    /// Find the feature index that deviates the most between the sequence and centroid.
    private static func findDominantChange(
        sequence: WeekSequence,
        centroid: [DayNucleotide]
    ) -> Int {
        let featureCount = DayNucleotide.featureCount
        var maxDiff = 0.0
        var maxIdx = 0

        for f in 0..<featureCount {
            var diff = 0.0
            let dayCount = min(sequence.nucleotides.count, centroid.count)
            for d in 0..<dayCount {
                let delta = sequence.nucleotides[d].features[f] - centroid[d].features[f]
                diff += delta * delta
            }
            if diff > maxDiff {
                maxDiff = diff
                maxIdx = f
            }
        }

        return maxIdx
    }
}
