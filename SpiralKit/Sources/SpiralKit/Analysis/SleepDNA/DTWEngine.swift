import Foundation

/// Dynamic Time Warping engine for comparing sleep week sequences.
///
/// Uses weighted Euclidean distance as the local cost function and standard DTW
/// with full cost-matrix backtracking for alignment path recovery.
public enum DTWEngine {

    // MARK: - Public API

    /// Full DTW between two WeekSequences.
    ///
    /// - Parameters:
    ///   - a: First week sequence (7 days).
    ///   - b: Second week sequence (7 days).
    ///   - weights: Optional 16-element weight vector (SleepBLOSUM weights).
    ///              Defaults to uniform weights of 1.0.
    /// - Returns: The DTW distance and the optimal alignment path as (row, col) index pairs.
    public static func distance(
        _ a: WeekSequence,
        _ b: WeekSequence,
        weights: [Double]? = nil
    ) -> (distance: Double, path: [(Int, Int)]) {
        dtw(
            rows: a.nucleotides.map(\.features),
            cols: b.nucleotides.map(\.features),
            weights: weights ?? Array(repeating: 1.0, count: DayNucleotide.featureCount)
        )
    }

    /// Partial DTW -- compare a partial week against a full week.
    ///
    /// The partial sequence (fewer than 7 days) is aligned against the full 7-day week.
    /// Useful for matching an in-progress week to historical patterns.
    ///
    /// - Parameters:
    ///   - partial: A sequence of 1..6 day nucleotides.
    ///   - full: A complete 7-day week sequence.
    ///   - weights: Optional 16-element weight vector. Defaults to uniform 1.0.
    /// - Returns: The DTW distance and the optimal alignment path.
    public static func partialDistance(
        partial: [DayNucleotide],
        full: WeekSequence,
        weights: [Double]? = nil
    ) -> (distance: Double, path: [(Int, Int)]) {
        dtw(
            rows: partial.map(\.features),
            cols: full.nucleotides.map(\.features),
            weights: weights ?? Array(repeating: 1.0, count: DayNucleotide.featureCount)
        )
    }

    // MARK: - Core DTW

    /// Standard DTW with cost matrix and backtracking.
    ///
    /// - Parameters:
    ///   - rows: Feature vectors for the "query" sequence (length M).
    ///   - cols: Feature vectors for the "reference" sequence (length N).
    ///   - weights: Per-feature weights for the Euclidean distance.
    /// - Returns: Cumulative DTW distance and the warping path from (0,0) to (M-1, N-1).
    private static func dtw(
        rows: [[Double]],
        cols: [[Double]],
        weights: [Double]
    ) -> (distance: Double, path: [(Int, Int)]) {
        let m = rows.count
        let n = cols.count
        guard m > 0, n > 0 else { return (0, []) }

        // Build cost matrix with +inf borders
        let inf = Double.infinity
        // dtw[i][j] = cumulative cost to align rows[0..i] with cols[0..j]
        var cost = [[Double]](repeating: [Double](repeating: inf, count: n), count: m)

        cost[0][0] = weightedEuclidean(rows[0], cols[0], weights)

        // First column
        for i in 1..<m {
            cost[i][0] = cost[i - 1][0] + weightedEuclidean(rows[i], cols[0], weights)
        }

        // First row
        for j in 1..<n {
            cost[0][j] = cost[0][j - 1] + weightedEuclidean(rows[0], cols[j], weights)
        }

        // Fill interior
        for i in 1..<m {
            for j in 1..<n {
                let local = weightedEuclidean(rows[i], cols[j], weights)
                cost[i][j] = local + min(cost[i - 1][j], cost[i][j - 1], cost[i - 1][j - 1])
            }
        }

        // Backtrack from (m-1, n-1) to (0, 0)
        var path: [(Int, Int)] = []
        var i = m - 1
        var j = n - 1
        path.append((i, j))

        while i > 0 || j > 0 {
            if i == 0 {
                j -= 1
            } else if j == 0 {
                i -= 1
            } else {
                let candidates = [
                    (i - 1, j - 1, cost[i - 1][j - 1]),
                    (i - 1, j, cost[i - 1][j]),
                    (i, j - 1, cost[i][j - 1]),
                ]
                let best = candidates.min(by: { $0.2 < $1.2 })!
                i = best.0
                j = best.1
            }
            path.append((i, j))
        }

        path.reverse()
        return (cost[m - 1][n - 1], path)
    }

    // MARK: - Distance

    /// Weighted Euclidean distance between two feature vectors.
    ///
    /// `sqrt( sum( w[k] * (a[k] - b[k])^2 ) )`
    private static func weightedEuclidean(_ a: [Double], _ b: [Double], _ w: [Double]) -> Double {
        let count = min(a.count, b.count, w.count)
        var sum = 0.0
        for k in 0..<count {
            let diff = a[k] - b[k]
            sum += w[k] * diff * diff
        }
        return sqrt(sum)
    }
}
