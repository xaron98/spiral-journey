import Foundation

// MARK: - Types

/// Mutual information value for a single hour-of-day window.
public struct MISWindow: Codable, Sendable {
    /// Hour of day (0-23).
    public let hourOfDay: Int
    /// Mutual information between C(t) and dH/dt at this hour.
    public let mutualInformation: Double
}

/// Windowed mutual information spectrum between circadian (C) and
/// homeostatic derivative (dH/dt) signals across 24 hours.
public struct MISResult: Codable, Sendable {
    /// 24 entries, one per hour of day.
    public let windows: [MISWindow]
    /// Hour with highest mutual information.
    public let peakHour: Int
    /// Hour with lowest mutual information.
    public let troughHour: Int
    /// Mean MI across all 24 hours.
    public let meanMI: Double
}

// MARK: - Computation

/// Mutual Information Spectrum (MIS): computes windowed MI between
/// circadian oscillation C(t) and the rate of change of homeostatic
/// sleep pressure dH/dt.
///
/// For each hour of day (0-23), collects all C and dH/dt values across
/// all days at that hour, then computes MI to reveal when the two
/// regulatory processes are most coupled.
public enum MutualInformationSpectrum {

    /// Number of histogram bins for MI discretization.
    private static let binCount = 5

    /// Minimum number of days required for meaningful MI estimation.
    private static let minimumDays = 7

    /// Compute the 24-hour MI spectrum between circadian and homeostatic signals.
    ///
    /// - Parameter records: Sleep records with cosinor parameters and hourly activity.
    /// - Returns: 24-hour MI profile, or nil if insufficient data.
    public static func compute(records: [SleepRecord]) -> MISResult? {
        guard records.count >= minimumDays else { return nil }

        let sorted = records.sorted { $0.day < $1.day }

        // Compute continuous Process S across all days
        let twoProcessPoints = TwoProcessModel.computeContinuous(sorted)

        // Organize points by (day, hour) for easy lookup
        // twoProcessPoints is ordered: day 0 hours 0..23, day 1 hours 0..23, etc.
        let numDays = sorted.count

        // For each hour, collect C values and dH/dt values across all days
        var cByHour = [[Double]](repeating: [], count: 24)
        var dhByHour = [[Double]](repeating: [], count: 24)

        for d in 0..<numDays {
            let baseIdx = d * 24

            for h in 0..<24 {
                let idx = baseIdx + h
                guard idx < twoProcessPoints.count else { continue }

                let point = twoProcessPoints[idx]

                // C(t) from cosinor
                let c = TwoProcessModel.processC(hour: Double(h), cosinor: sorted[d].cosinor)
                cByHour[h].append(c)

                // dH/dt: finite difference H(t+1) - H(t)
                let nextIdx = idx + 1
                if nextIdx < twoProcessPoints.count && nextIdx < (d + 1) * 24 {
                    let dh = twoProcessPoints[nextIdx].s - point.s
                    dhByHour[h].append(dh)
                } else if h < 23 {
                    // Within same day but at boundary — use wrap
                    let wrapIdx = baseIdx + h + 1
                    if wrapIdx < twoProcessPoints.count {
                        let dh = twoProcessPoints[wrapIdx].s - point.s
                        dhByHour[h].append(dh)
                    }
                }
            }
        }

        // Compute MI for each hour
        var windows = [MISWindow]()
        windows.reserveCapacity(24)

        for h in 0..<24 {
            let cValues = cByHour[h]
            let dhValues = dhByHour[h]
            let count = min(cValues.count, dhValues.count)

            let mi: Double
            if count >= 3 {
                mi = mutualInformation(
                    Array(cValues.prefix(count)),
                    Array(dhValues.prefix(count))
                )
            } else {
                mi = 0
            }

            windows.append(MISWindow(hourOfDay: h, mutualInformation: mi))
        }

        // Find peak and trough
        let peakHour = windows.max(by: { $0.mutualInformation < $1.mutualInformation })?.hourOfDay ?? 0
        let troughHour = windows.min(by: { $0.mutualInformation < $1.mutualInformation })?.hourOfDay ?? 0
        let meanMI = windows.reduce(0.0) { $0 + $1.mutualInformation } / 24.0

        return MISResult(
            windows: windows,
            peakHour: peakHour,
            troughHour: troughHour,
            meanMI: meanMI
        )
    }

    // MARK: - Mutual Information (same algorithm as SleepBLOSUM)

    /// Compute mutual information between two equal-length signal series.
    ///
    /// Both signals are discretized into `binCount` equal-width bins.
    /// MI = H(X) + H(Y) - H(X,Y)
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
    private static func discretize(_ signal: [Double]) -> [Int] {
        guard let lo = signal.min(), let hi = signal.max() else { return [] }

        let range = hi - lo
        if range < 1e-15 {
            return [Int](repeating: 0, count: signal.count)
        }

        let bc = Double(binCount)
        return signal.map { value in
            let normalized = (value - lo) / range
            let bin = Int(normalized * bc)
            return min(bin, binCount - 1)
        }
    }

    /// Shannon entropy H(X) from bin indices.
    private static func shannonEntropy(_ bins: [Int], n: Int) -> Double {
        var counts = [Int: Int]()
        for b in bins { counts[b, default: 0] += 1 }
        var h = 0.0
        let nd = Double(n)
        for (_, count) in counts {
            let p = Double(count) / nd
            if p > 0 { h -= p * log(p) }
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
            if p > 0 { h -= p * log(p) }
        }
        return h
    }
}
