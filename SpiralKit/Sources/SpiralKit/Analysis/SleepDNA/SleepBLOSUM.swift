import Foundation

/// Learned per-feature weight matrix for SleepDNA comparison.
///
/// Inspired by the BLOSUM substitution matrices in bioinformatics, SleepBLOSUM
/// assigns importance weights to each of the 16 DayNucleotide features based on
/// how predictive they are of next-day sleep quality.
///
/// Weights are learned via mutual information between each feature series and
/// next-day sleep quality (feature index 15).
public struct SleepBLOSUM: Codable, Sendable {

    /// 16 per-feature weights, always > 0.
    public var weights: [Double]

    /// Uniform weights (all 1.0) used when insufficient data is available.
    public static let initial = SleepBLOSUM(weights: Array(repeating: 1.0, count: DayNucleotide.featureCount))

    /// Minimum number of nucleotides required to learn meaningful weights.
    private static let minimumSamples = 14

    /// Number of bins for discretizing continuous features in MI calculation.
    private static let binCount = 5

    /// Maximum weight after normalization.
    private static let maxWeight = 3.0

    // MARK: - Learning

    /// Learn feature weights from historical nucleotide data via mutual information.
    ///
    /// For each of the 16 features, computes the mutual information between that
    /// feature's time series and next-day sleep quality. Features that better predict
    /// tomorrow's sleep quality receive higher weights.
    ///
    /// - Parameter nucleotides: Historical day nucleotides, sorted or unsorted.
    /// - Returns: A `SleepBLOSUM` with learned weights, or `.initial` if fewer than 14 samples.
    public static func learn(from nucleotides: [DayNucleotide]) -> SleepBLOSUM {
        guard nucleotides.count >= minimumSamples else { return .initial }

        let sorted = nucleotides.sorted { $0.day < $1.day }

        // Build next-day quality series: for each day i, pair feature[i] with quality[i+1]
        let qualityIndex = DayNucleotide.Feature.sleepQuality.rawValue
        let nextDayQuality: [Double] = (0..<(sorted.count - 1)).map { i in
            sorted[i + 1].features[qualityIndex]
        }

        let featureCount = DayNucleotide.featureCount
        var rawWeights = [Double](repeating: 0, count: featureCount)

        for f in 0..<featureCount {
            let featureSeries: [Double] = (0..<(sorted.count - 1)).map { i in
                sorted[i].features[f]
            }
            let mi = mutualInformation(featureSeries, nextDayQuality)
            rawWeights[f] = max(0.1, mi * 10.0)
        }

        // Normalize so max weight = maxWeight
        let currentMax = rawWeights.max() ?? 1.0
        if currentMax > 0 {
            let scale = maxWeight / currentMax
            for i in 0..<featureCount {
                rawWeights[i] *= scale
            }
        }

        return SleepBLOSUM(weights: rawWeights)
    }

    // MARK: - Mutual Information

    /// Compute mutual information between two equal-length signal series.
    ///
    /// Both signals are discretized into `binCount` equal-width bins.
    /// MI = H(X) + H(Y) - H(X,Y)
    ///
    /// - Returns: Mutual information in nats (>= 0).
    private static func mutualInformation(_ x: [Double], _ y: [Double]) -> Double {
        let n = min(x.count, y.count)
        guard n > 0 else { return 0 }

        let binsX = discretize(x)
        let binsY = discretize(y)

        let hX = shannonEntropy(binsX, n: n)
        let hY = shannonEntropy(binsY, n: n)
        let hXY = jointEntropy(binsX, binsY, n: n)

        return max(0, hX + hY - hXY)
    }

    /// Discretize a signal into `binCount` equal-width bins.
    ///
    /// Returns an array of bin indices (0..<binCount).
    private static func discretize(_ signal: [Double]) -> [Int] {
        guard let lo = signal.min(), let hi = signal.max() else { return [] }

        let range = hi - lo
        if range < 1e-15 {
            // Constant signal: all in bin 0
            return [Int](repeating: 0, count: signal.count)
        }

        let bc = Double(binCount)
        return signal.map { value in
            let normalized = (value - lo) / range // [0, 1]
            let bin = Int(normalized * bc)
            return min(bin, binCount - 1) // clamp top edge
        }
    }

    /// Shannon entropy H(X) from bin indices.
    private static func shannonEntropy(_ bins: [Int], n: Int) -> Double {
        var counts = [Int: Int]()
        for b in bins {
            counts[b, default: 0] += 1
        }
        var h = 0.0
        let nd = Double(n)
        for (_, count) in counts {
            let p = Double(count) / nd
            if p > 0 {
                h -= p * log(p)
            }
        }
        return h
    }

    /// Joint entropy H(X,Y) from paired bin indices.
    private static func jointEntropy(_ binsX: [Int], _ binsY: [Int], n: Int) -> Double {
        var counts = [Int: Int]()
        let bc = binCount
        for i in 0..<n {
            let key = binsX[i] * bc + binsY[i]
            counts[key, default: 0] += 1
        }
        var h = 0.0
        let nd = Double(n)
        for (_, count) in counts {
            let p = Double(count) / nd
            if p > 0 {
                h -= p * log(p)
            }
        }
        return h
    }
}
