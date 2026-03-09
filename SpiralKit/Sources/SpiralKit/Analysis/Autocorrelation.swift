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
}
