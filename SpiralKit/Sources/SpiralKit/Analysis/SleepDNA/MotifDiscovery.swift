import Foundation

/// A recurring weekly sleep pattern discovered via agglomerative clustering of WeekSequences.
public struct SleepMotif: Identifiable, Codable, Sendable {
    public let id: UUID
    /// Auto-generated name based on dominant feature deviation (e.g. "Late-night", "Active-week").
    public let name: String
    /// Always 7 (weekly motifs).
    public let windowSize: Int
    /// Element-wise average pattern across all member sequences.
    public let centroid: [DayNucleotide]
    /// Number of weeks that belong to this motif.
    public let instanceCount: Int
    /// Indices into the input `WeekSequence` array for each member.
    public let instanceWeekIndices: [Int]
    /// Mean sleep quality across all member nucleotides.
    public let avgQuality: Double
}

/// Discovers recurring motifs in weekly sleep sequences using DTW + agglomerative clustering.
public enum MotifDiscovery {

    /// Minimum number of input sequences required to run discovery.
    private static let minimumSequences = 4

    /// Maximum number of sequences to include in the distance matrix. Beyond this we randomly
    /// sample to keep computation tractable (DTW is O(n^2) pairwise).
    private static let maxSequences = 200

    /// Maximum number of motifs to return.
    private static let maxMotifs = 10

    /// Default DTW distance threshold for merging clusters. Tuned for 16-feature nucleotides
    /// with uniform weights.
    public static let defaultThreshold = 8.0

    // MARK: - Public API

    /// Discover motifs from a set of week sequences.
    ///
    /// - Parameters:
    ///   - sequences: All `WeekSequence` values from the user's history.
    ///   - weights: Optional BLOSUM weights for DTW. Defaults to uniform 1.0.
    ///   - threshold: Maximum single-linkage distance for merging clusters.
    /// - Returns: Up to 10 `SleepMotif` values sorted by instance count descending.
    public static func discover(
        sequences: [WeekSequence],
        weights: [Double]? = nil,
        threshold: Double = defaultThreshold
    ) -> [SleepMotif] {
        guard sequences.count >= minimumSequences else { return [] }

        // Sample if too many
        let (sampled, originalIndices) = sampleIfNeeded(sequences)

        // Pairwise DTW distance matrix
        let n = sampled.count
        let w = weights ?? Array(repeating: 1.0, count: DayNucleotide.featureCount)
        var dist = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = DTWEngine.distance(sampled[i], sampled[j], weights: w).distance
                dist[i][j] = d
                dist[j][i] = d
            }
        }

        // Agglomerative clustering (single-linkage)
        let clusters = agglomerativeClustering(distanceMatrix: dist, threshold: threshold)

        // Convert clusters to motifs (only those with >= 2 members)
        let globalMean = computeGlobalMean(sampled)
        var motifs: [SleepMotif] = []

        for cluster in clusters {
            guard cluster.count >= 2 else { continue }

            let memberSequences = cluster.map { sampled[$0] }
            let weekIndices = cluster.map { originalIndices[$0] }
            let centroid = computeCentroid(memberSequences)
            let avgQuality = computeAverageQuality(memberSequences)
            let name = autoName(centroid: centroid, globalMean: globalMean, index: motifs.count)

            motifs.append(SleepMotif(
                id: UUID(),
                name: name,
                windowSize: 7,
                centroid: centroid,
                instanceCount: cluster.count,
                instanceWeekIndices: weekIndices.sorted(),
                avgQuality: avgQuality
            ))
        }

        // Sort by instance count descending, cap at maxMotifs
        motifs.sort { $0.instanceCount > $1.instanceCount }
        return Array(motifs.prefix(maxMotifs))
    }

    // MARK: - Sampling

    /// If the input exceeds `maxSequences`, randomly sample down to that limit.
    /// Returns (sampled sequences, mapping from sampled index -> original index).
    private static func sampleIfNeeded(
        _ sequences: [WeekSequence]
    ) -> (sampled: [WeekSequence], originalIndices: [Int]) {
        if sequences.count <= maxSequences {
            return (sequences, Array(0..<sequences.count))
        }
        var indices = Array(0..<sequences.count)
        // Deterministic shuffle using a simple LCG seeded with count
        var rng = SimpleLCG(seed: UInt64(sequences.count))
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            indices.swapAt(i, j)
        }
        let selected = Array(indices.prefix(maxSequences))
        return (selected.map { sequences[$0] }, selected)
    }

    // MARK: - Agglomerative Clustering (Single-Linkage)

    /// Perform single-linkage agglomerative clustering.
    ///
    /// Starting with each element in its own cluster, repeatedly merge the two closest
    /// clusters until the minimum inter-cluster distance exceeds the threshold.
    ///
    /// - Returns: Array of clusters, each cluster being an array of original element indices.
    private static func agglomerativeClustering(
        distanceMatrix: [[Double]],
        threshold: Double
    ) -> [[Int]] {
        let n = distanceMatrix.count
        guard n > 0 else { return [] }

        // Each cluster is a set of original indices
        var clusters: [[Int]] = (0..<n).map { [$0] }
        // Track which clusters are still active
        var active = Set(0..<n)

        // Inter-cluster distance (single-linkage = min of pairwise)
        // We maintain a mutable copy of the distance matrix indexed by cluster ID
        var clusterDist = distanceMatrix

        while active.count > 1 {
            // Find the closest pair of active clusters
            var bestI = -1
            var bestJ = -1
            var bestDist = Double.infinity

            let activeArray = Array(active).sorted()
            for ai in 0..<activeArray.count {
                for aj in (ai + 1)..<activeArray.count {
                    let ci = activeArray[ai]
                    let cj = activeArray[aj]
                    if clusterDist[ci][cj] < bestDist {
                        bestDist = clusterDist[ci][cj]
                        bestI = ci
                        bestJ = cj
                    }
                }
            }

            guard bestDist <= threshold else { break }

            // Merge bestJ into bestI
            clusters[bestI].append(contentsOf: clusters[bestJ])
            active.remove(bestJ)

            // Update distances: single-linkage uses min
            for ci in active where ci != bestI {
                let newDist = min(clusterDist[bestI][ci], clusterDist[bestJ][ci])
                clusterDist[bestI][ci] = newDist
                clusterDist[ci][bestI] = newDist
            }
        }

        return active.sorted().map { clusters[$0] }
    }

    // MARK: - Centroid

    /// Compute the centroid of a set of week sequences by averaging each day-position's features.
    private static func computeCentroid(_ sequences: [WeekSequence]) -> [DayNucleotide] {
        guard let first = sequences.first else { return [] }
        let dayCount = first.nucleotides.count
        let featureCount = DayNucleotide.featureCount
        let n = Double(sequences.count)

        return (0..<dayCount).map { dayIdx in
            var avgFeatures = [Double](repeating: 0, count: featureCount)
            for seq in sequences {
                let features = seq.nucleotides[dayIdx].features
                for f in 0..<featureCount {
                    avgFeatures[f] += features[f]
                }
            }
            for f in 0..<featureCount {
                avgFeatures[f] /= n
            }
            // Use the day index from the first sequence as a representative
            return DayNucleotide(day: first.nucleotides[dayIdx].day, features: avgFeatures)
        }
    }

    // MARK: - Quality

    /// Average sleep quality across all nucleotides in the given sequences.
    private static func computeAverageQuality(_ sequences: [WeekSequence]) -> Double {
        let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
        var total = 0.0
        var count = 0
        for seq in sequences {
            for nuc in seq.nucleotides {
                total += nuc.features[qualityIdx]
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - Auto-Naming

    /// Compute the global mean feature vector across all sequences and all days.
    private static func computeGlobalMean(_ sequences: [WeekSequence]) -> [Double] {
        let featureCount = DayNucleotide.featureCount
        var sum = [Double](repeating: 0, count: featureCount)
        var count = 0
        for seq in sequences {
            for nuc in seq.nucleotides {
                for f in 0..<featureCount {
                    sum[f] += nuc.features[f]
                }
                count += 1
            }
        }
        guard count > 0 else { return sum }
        return sum.map { $0 / Double(count) }
    }

    /// Generate a human-readable name based on the centroid's dominant deviation from the global mean.
    private static func autoName(centroid: [DayNucleotide], globalMean: [Double], index: Int) -> String {
        let featureCount = DayNucleotide.featureCount

        // Compute mean feature values across the centroid's 7 days
        var centroidMean = [Double](repeating: 0, count: featureCount)
        for nuc in centroid {
            for f in 0..<featureCount {
                centroidMean[f] += nuc.features[f]
            }
        }
        let dayCount = Double(centroid.count)
        for f in 0..<featureCount {
            centroidMean[f] /= dayCount
        }

        // Find the feature with the largest signed deviation from global mean
        var bestFeature = -1
        var bestDeviation = 0.0
        for f in 0..<featureCount {
            let deviation = centroidMean[f] - globalMean[f]
            if abs(deviation) > abs(bestDeviation) {
                bestDeviation = deviation
                bestFeature = f
            }
        }

        guard bestFeature >= 0 else { return "Pattern-\(index + 1)" }

        // Name based on feature
        switch DayNucleotide.Feature(rawValue: bestFeature) {
        case .bedtimeSin, .bedtimeCos:
            return bestDeviation > 0 ? "Late-night" : "Early-bird"
        case .exercise:
            return bestDeviation > 0 ? "Active-week" : "Sedentary-week"
        case .caffeine:
            return bestDeviation > 0 ? "Caffeine-heavy" : "Low-caffeine"
        case .sleepQuality:
            return bestDeviation < 0 ? "Poor-sleep" : "Good-sleep"
        case .isWeekend:
            return bestDeviation > 0 ? "Weekend-mode" : "Weekday-mode"
        case .alcohol:
            return bestDeviation > 0 ? "High-alcohol" : "Low-alcohol"
        case .stress:
            return bestDeviation > 0 ? "High-stress" : "Low-stress"
        case .sleepDuration:
            return bestDeviation > 0 ? "Long-sleep" : "Short-sleep"
        case .melatonin:
            return bestDeviation > 0 ? "Melatonin-use" : "No-melatonin"
        case .driftMinutes:
            return bestDeviation > 0 ? "Late-drift" : "Early-drift"
        case .processS:
            return bestDeviation > 0 ? "High-pressure" : "Low-pressure"
        case .cosinorAcrophase:
            return bestDeviation > 0 ? "Late-acrophase" : "Early-acrophase"
        case .cosinorR2:
            return bestDeviation > 0 ? "High-rhythm" : "Low-rhythm"
        case .wakeupSin, .wakeupCos:
            return bestDeviation > 0 ? "Late-wakeup" : "Early-wakeup"
        case .none:
            return "Pattern-\(index + 1)"
        }
    }

    // MARK: - Simple RNG

    /// A simple linear congruential generator for deterministic sampling.
    private struct SimpleLCG: Sendable {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
    }
}
