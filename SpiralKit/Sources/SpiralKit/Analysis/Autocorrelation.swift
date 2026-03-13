import Foundation

/// Radial autocorrelation matrix ρ(θ, l).
///
/// For each angular position θ (hour of day) and lag l (days),
/// computes the Pearson correlation between activity at (θ, d) and (θ, d+l).
/// Reveals which phases of the day are most stable across consecutive days.
///
/// Port of src/utils/autocorrelation.js from the Spiral Journey web project.
public enum Autocorrelation {

    public struct CorrelationPoint: Sendable {
        public let hour: Int
        public let lag: Int
        public let correlation: Double
    }

    /// Compute the full radial autocorrelation matrix.
    /// - Parameters:
    ///   - records: Array of SleepRecord objects
    ///   - maxLag: Maximum day lag to compute (default 7)
    /// - Returns: Flat array of correlation values for each (hour, lag) pair
    public static func compute(_ records: [SleepRecord], maxLag: Int = 7) -> [CorrelationPoint] {
        var result: [CorrelationPoint] = []
        let numDays = records.count

        for h in 0..<24 {
            // Extract activity values for this hour across all days
            let values: [Double] = records.map { day in
                day.hourlyActivity.first { $0.hour == h }.map(\.activity) ?? 0
            }

            for lag in 1...min(maxLag, numDays - 1) {
                let n = numDays - lag
                guard n >= 3 else {
                    result.append(CorrelationPoint(hour: h, lag: lag, correlation: 0))
                    continue
                }

                var sumX = 0.0, sumY = 0.0
                for d in 0..<n {
                    sumX += values[d]
                    sumY += values[d + lag]
                }
                let meanX = sumX / Double(n)
                let meanY = sumY / Double(n)

                var covXY = 0.0, varX = 0.0, varY = 0.0
                for d in 0..<n {
                    let dx = values[d] - meanX
                    let dy = values[d + lag] - meanY
                    covXY += dx * dy
                    varX  += dx * dx
                    varY  += dy * dy
                }

                let denom = sqrt(varX * varY)
                let corr = denom > 0 ? covXY / denom : 0

                result.append(CorrelationPoint(hour: h, lag: lag, correlation: corr))
            }
        }
        return result
    }

    // MARK: - Extended autocorrelation with significance testing

    /// Result of a single lag analysis with statistical significance.
    public struct SignificantCorrelation: Sendable {
        public let hour: Int
        public let lag: Int
        public let correlation: Double
        public let pValue: Double
        public let isSignificant: Bool   // p < 0.05
    }

    /// Compute autocorrelation at extended lags with permutation-based significance.
    ///
    /// Extends beyond 7-day lag to capture circaseptano (14d) and circalunar (28d)
    /// rhythms. Each correlation is tested against a null distribution generated
    /// by shuffling the time series (permutation test).
    ///
    /// - Parameters:
    ///   - records: Array of SleepRecord objects
    ///   - lags: Lag values (in days) to test. Default: [1, 2, 7, 14, 28]
    ///   - permutations: Number of shuffles for significance test (default 200)
    ///   - seed: Optional seed for reproducible permutation shuffles
    /// - Returns: Array of SignificantCorrelation for each (hour, lag) pair
    public static func computeExtended(
        _ records: [SleepRecord],
        lags: [Int] = [1, 2, 7, 14, 28],
        permutations: Int = 200,
        seed: UInt64? = nil
    ) -> [SignificantCorrelation] {
        var result: [SignificantCorrelation] = []
        let numDays = records.count

        for h in 0..<24 {
            let values: [Double] = records.map { day in
                day.hourlyActivity.first { $0.hour == h }.map(\.activity) ?? 0
            }

            for lag in lags {
                let n = numDays - lag
                guard n >= 3 else {
                    result.append(SignificantCorrelation(
                        hour: h, lag: lag, correlation: 0, pValue: 1.0, isSignificant: false))
                    continue
                }

                let observed = pearson(values, lag: lag, n: n)

                // Permutation test: count how many shuffled correlations ≥ |observed|
                var exceedCount = 0
                var rng = SeededRNG(seed: (seed ?? UInt64(arc4random())) &+ UInt64(h) &* 31 &+ UInt64(lag) &* 17)
                for _ in 0..<permutations {
                    var shuffled = values
                    fisherYatesShuffle(&shuffled, using: &rng)
                    let permCorr = pearson(shuffled, lag: lag, n: n)
                    if abs(permCorr) >= abs(observed) { exceedCount += 1 }
                }

                let pValue = Double(exceedCount + 1) / Double(permutations + 1)
                result.append(SignificantCorrelation(
                    hour: h, lag: lag,
                    correlation: observed,
                    pValue: pValue,
                    isSignificant: pValue < 0.05))
            }
        }
        return result
    }

    // MARK: - Private helpers

    /// Pearson correlation between values[0..<n] and values[lag..<lag+n].
    private static func pearson(_ values: [Double], lag: Int, n: Int) -> Double {
        var sumX = 0.0, sumY = 0.0
        for d in 0..<n {
            sumX += values[d]
            sumY += values[d + lag]
        }
        let meanX = sumX / Double(n)
        let meanY = sumY / Double(n)

        var covXY = 0.0, varX = 0.0, varY = 0.0
        for d in 0..<n {
            let dx = values[d] - meanX
            let dy = values[d + lag] - meanY
            covXY += dx * dy
            varX  += dx * dx
            varY  += dy * dy
        }

        let denom = sqrt(varX * varY)
        return denom > 0 ? covXY / denom : 0
    }

    /// Fisher–Yates shuffle using the seeded RNG.
    private static func fisherYatesShuffle(_ array: inout [Double], using rng: inout SeededRNG) {
        for i in stride(from: array.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            array.swapAt(i, j)
        }
    }

    /// Simple seeded RNG for reproducible permutation tests (SplitMix64).
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
    }
}
