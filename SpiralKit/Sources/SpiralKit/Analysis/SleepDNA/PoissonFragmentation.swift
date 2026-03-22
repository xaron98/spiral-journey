import Foundation

// MARK: - Output Types

/// Per-night Poisson rate data.
public struct DayRate: Codable, Sendable {
    /// Zero-based day index from the source SleepRecord.
    public let day: Int
    /// Number of awake phases observed within the bedtime-wake window.
    public let awakenings: Int
    /// Baseline λ used as the expected rate for this night.
    public let expectedRate: Double
    /// P(X >= awakenings | λ) — tail probability under the Poisson model.
    public let pValue: Double
    /// True when pValue < 0.05.
    public let isAnomaly: Bool

    public init(
        day: Int,
        awakenings: Int,
        expectedRate: Double,
        pValue: Double,
        isAnomaly: Bool
    ) {
        self.day = day
        self.awakenings = awakenings
        self.expectedRate = expectedRate
        self.pValue = pValue
        self.isAnomaly = isAnomaly
    }
}

/// Full output of the Poisson fragmentation analysis.
public struct PoissonFragmentationResult: Codable, Sendable {
    /// Mean awakenings per night — the estimated Poisson rate λ.
    public let baselineRate: Double
    /// Per-night breakdown of observed counts and tail probabilities.
    public let nightlyRates: [DayRate]
    /// Day indices where the Poisson tail probability was < 0.05.
    public let anomalousNights: [Int]
    /// p-value from the chi-squared goodness-of-fit test.
    public let chiSquaredPValue: Double
    /// True when the data is consistent with a Poisson distribution (p > 0.05).
    public let followsPoisson: Bool

    public init(
        baselineRate: Double,
        nightlyRates: [DayRate],
        anomalousNights: [Int],
        chiSquaredPValue: Double,
        followsPoisson: Bool
    ) {
        self.baselineRate = baselineRate
        self.nightlyRates = nightlyRates
        self.anomalousNights = anomalousNights
        self.chiSquaredPValue = chiSquaredPValue
        self.followsPoisson = followsPoisson
    }
}

// MARK: - Main Analyzer

/// Models nightly awakenings as a Poisson process and tests goodness-of-fit.
public enum PoissonFragmentation {

    /// Analyze fragmentation across all provided records.
    ///
    /// - Parameter records: Sleep records in any order. Needs at least 2 nights for
    ///   the chi-squared test to be meaningful; with 0 or 1 record the result is
    ///   returned with safe default values.
    /// - Returns: A ``PoissonFragmentationResult`` with per-night rates, anomalies,
    ///   and the overall Poisson fit quality.
    public static func analyze(records: [SleepRecord]) -> PoissonFragmentationResult {
        guard records.count >= 2 else {
            // Degenerate case: return safe defaults
            let counts = records.map { countAwakenings(record: $0) }
            let rate = counts.first.map(Double.init) ?? 0.0
            let nightlyRates: [DayRate] = records.enumerated().map { (_, rec) in
                DayRate(day: rec.day, awakenings: counts[0], expectedRate: rate,
                        pValue: 1.0, isAnomaly: false)
            }
            return PoissonFragmentationResult(
                baselineRate: rate,
                nightlyRates: nightlyRates,
                anomalousNights: [],
                chiSquaredPValue: 1.0,
                followsPoisson: true
            )
        }

        // Step 1: Count awakenings per night
        let sorted = records.sorted { $0.day < $1.day }
        let counts = sorted.map { countAwakenings(record: $0) }

        // Step 2: Baseline λ = mean awakenings
        let totalCount = counts.reduce(0, +)
        let lambda = Double(totalCount) / Double(counts.count)

        // Step 3: Per-night tail probability P(X >= k | λ)
        let anomalyThreshold = 0.05
        var nightlyRates: [DayRate] = []
        var anomalousNights: [Int] = []

        for (idx, record) in sorted.enumerated() {
            let k = counts[idx]
            let pValue = poissonCDFComplement(k: k, lambda: lambda)
            let isAnomaly = pValue < anomalyThreshold
            nightlyRates.append(DayRate(
                day: record.day,
                awakenings: k,
                expectedRate: lambda,
                pValue: pValue,
                isAnomaly: isAnomaly
            ))
            if isAnomaly {
                anomalousNights.append(record.day)
            }
        }

        // Step 4: Chi-squared goodness-of-fit
        let chiPValue = chiSquaredGoodnessOfFit(observed: counts, lambda: lambda)

        return PoissonFragmentationResult(
            baselineRate: lambda,
            nightlyRates: nightlyRates,
            anomalousNights: anomalousNights,
            chiSquaredPValue: chiPValue,
            followsPoisson: chiPValue > anomalyThreshold
        )
    }

    // MARK: - Awakening Counter

    /// Count awake-phase intervals that fall within [bedtimeHour, wakeupHour].
    ///
    /// The function handles midnight-crossing windows (bedtime > wakeup in clock hours).
    private static func countAwakenings(record: SleepRecord) -> Int {
        let bedtime = record.bedtimeHour
        let wakeup  = record.wakeupHour

        return record.phases.filter { interval in
            guard interval.phase == .awake else { return false }
            let h = interval.hour
            if bedtime <= wakeup {
                // Normal window e.g. 01:00 – 07:00
                return h >= bedtime && h < wakeup
            } else {
                // Midnight-crossing window e.g. 23:00 – 07:00
                return h >= bedtime || h < wakeup
            }
        }.count
    }

    // MARK: - Poisson Math

    /// P(X = k) for a Poisson distribution with rate λ.
    ///
    /// Uses log-space arithmetic to avoid overflow for large k.
    static func poissonPMF(k: Int, lambda: Double) -> Double {
        guard lambda > 0, k >= 0 else { return k == 0 ? 1.0 : 0.0 }
        // log P = k·log(λ) - λ - log(k!)
        var logFactK = 0.0
        for i in 2...max(2, k) {
            if i <= k { logFactK += log(Double(i)) }
        }
        let logP = Double(k) * log(lambda) - lambda - logFactK
        return exp(logP)
    }

    /// P(X >= k | λ) = 1 - Σ_{i=0}^{k-1} P(X = i | λ).
    static func poissonCDFComplement(k: Int, lambda: Double) -> Double {
        guard k > 0 else { return 1.0 }
        var cdf = 0.0
        for i in 0..<k {
            cdf += poissonPMF(k: i, lambda: lambda)
            if cdf >= 1.0 { return 0.0 }
        }
        return max(0.0, 1.0 - cdf)
    }

    // MARK: - Chi-Squared Test

    /// Chi-squared goodness-of-fit: compare observed awakening-count frequencies
    /// against the theoretical Poisson(λ) distribution.
    ///
    /// Returns a p-value using the regularized upper incomplete gamma function
    /// approximation (Wilson-Hilferty transform).
    static func chiSquaredGoodnessOfFit(observed: [Int], lambda: Double) -> Double {
        guard !observed.isEmpty, lambda > 0 else { return 1.0 }

        let n = Double(observed.count)
        let maxBin = (observed.max() ?? 0) + 1

        // Build observed frequency table
        var obsFreq = [Double](repeating: 0, count: maxBin + 1)
        for k in observed {
            let bin = min(k, maxBin)
            obsFreq[bin] += 1
        }

        // Merge tail bins so E_i >= 1 (standard chi-squared requirement)
        var bins: [(obs: Double, exp: Double)] = []
        var accObs = 0.0
        var accExp = 0.0

        for bin in 0...maxBin {
            let expProb: Double
            if bin < maxBin {
                expProb = poissonPMF(k: bin, lambda: lambda)
            } else {
                // Tail: P(X >= maxBin)
                expProb = max(0.0, 1.0 - (0..<maxBin).reduce(0.0) { $0 + poissonPMF(k: $1, lambda: lambda) })
            }
            accObs += obsFreq[bin]
            accExp += expProb * n

            if accExp >= 1.0 || bin == maxBin {
                bins.append((obs: accObs, exp: accExp))
                accObs = 0
                accExp = 0
            }
        }

        // Need at least 2 bins for a meaningful test
        guard bins.count >= 2 else { return 1.0 }

        // χ² statistic
        let chiSq = bins.reduce(0.0) { sum, b in
            guard b.exp > 0 else { return sum }
            let diff = b.obs - b.exp
            return sum + (diff * diff) / b.exp
        }

        // Degrees of freedom = bins - 1 - 1 (estimated λ)
        let df = max(1, bins.count - 2)

        // p-value = P(χ²(df) > chiSq)
        return chiSquaredPValue(chiSq: chiSq, df: df)
    }

    /// Approximate p-value P(χ²(df) > x) using the regularized upper incomplete
    /// gamma function via the Wilson-Hilferty normal approximation.
    ///
    /// For df <= 100 this is accurate to ~3 significant figures.
    private static func chiSquaredPValue(chiSq: Double, df: Int) -> Double {
        guard chiSq > 0, df > 0 else { return 1.0 }
        // Wilson-Hilferty approximation: χ²/df ≈ Normal
        // z = ((chiSq/df)^(1/3) - (1 - 2/(9*df))) / sqrt(2/(9*df))
        let k = Double(df)
        let term = 2.0 / (9.0 * k)
        let z = (pow(chiSq / k, 1.0 / 3.0) - (1.0 - term)) / sqrt(term)
        // P(Z > z) for standard normal
        return normalSurvival(z: z)
    }

    /// P(Z > z) for a standard normal using Abramowitz & Stegun rational approximation.
    private static func normalSurvival(z: Double) -> Double {
        if z < -8.0 { return 1.0 }
        if z >  8.0 { return 0.0 }
        // Use erfc
        let x = z / sqrt(2.0)
        return 0.5 * erfc(x)
    }
}
