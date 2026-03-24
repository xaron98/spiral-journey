import Foundation

/// Lomb-Scargle Periodogram Engine
///
/// Detects periodic components in unevenly-sampled time series.
/// Used to find circadian (~24h), weekly (~168h), biweekly (~336h),
/// and menstrual (~672h) rhythms in sleep and health data.
///
/// References:
///   - Lomb, N.R. (1976). Least-squares frequency analysis of unequally spaced data.
///   - Scargle, J.D. (1982). Studies in astronomical time series analysis.
///   - VanderPlas, J.T. (2018). Understanding the Lomb-Scargle Periodogram.
public enum LombScargle {

    // MARK: - Types

    /// Biological signal types that can be analyzed.
    public enum Signal: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
        case sleepMidpoint
        case sleepDuration
        case cosinorAmplitude
        case restingHR
        case nocturnalHRV
    }

    /// Labels for known biological periods.
    public enum PeakLabel: String, Codable, Sendable, Equatable {
        case circadian   // ~24h
        case weekly      // ~168h
        case biweekly    // ~336h
        case menstrual   // ~672h
    }

    /// A detected spectral peak.
    public struct Peak: Codable, Sendable, Equatable {
        /// Period in hours at the peak.
        public let period: Double
        /// Lomb-Scargle power at the peak.
        public let power: Double
        /// Optional biological label if near a known period.
        public let label: PeakLabel?

        public init(period: Double, power: Double, label: PeakLabel? = nil) {
            self.period = period
            self.power = power
            self.label = label
        }
    }

    /// Full result of a Lomb-Scargle periodogram computation.
    public struct PeriodogramResult: Codable, Sendable {
        /// The signal that was analyzed.
        public let signal: Signal
        /// Period values (hours) for each frequency bin.
        public let periods: [Double]
        /// Normalized Lomb-Scargle power at each period.
        public let power: [Double]
        /// Significance threshold (Bonferroni-corrected p < 0.01).
        public let significanceThreshold: Double
        /// Detected peaks above the significance threshold.
        public let peaks: [Peak]

        /// True if no meaningful result could be computed.
        public var isEmpty: Bool { peaks.isEmpty && power.isEmpty }

        public init(signal: Signal, periods: [Double], power: [Double],
                    significanceThreshold: Double, peaks: [Peak]) {
            self.signal = signal
            self.periods = periods
            self.power = power
            self.significanceThreshold = significanceThreshold
            self.peaks = peaks
        }

        /// An empty result for when computation is not possible.
        public static func empty(signal: Signal) -> PeriodogramResult {
            PeriodogramResult(signal: signal, periods: [], power: [],
                              significanceThreshold: 0, peaks: [])
        }
    }

    // MARK: - Core Algorithm

    /// Minimum number of data points required for a meaningful periodogram.
    public static let minimumDataPoints = 14

    /// Compute the Lomb-Scargle periodogram for a time series.
    ///
    /// - Parameters:
    ///   - times: Observation times in hours.
    ///   - values: Observed values (same length as times).
    ///   - signal: The signal type being analyzed.
    ///   - minPeriod: Minimum period to search (hours). Default 20.
    ///   - maxPeriod: Maximum period to search (hours). Default 720.
    ///   - numFreqs: Number of frequency bins. Default 500.
    /// - Returns: PeriodogramResult with power spectrum and detected peaks.
    public static func compute(
        times: [Double],
        values: [Double],
        signal: Signal,
        minPeriod: Double = 20,
        maxPeriod: Double = 720,
        numFreqs: Int = 500
    ) -> PeriodogramResult {
        // Validate inputs
        guard times.count == values.count,
              times.count >= minimumDataPoints,
              minPeriod < maxPeriod,
              minPeriod > 0,
              numFreqs > 0 else {
            return .empty(signal: signal)
        }

        let n = times.count

        // Mean-center the values
        let mean = values.reduce(0, +) / Double(n)
        let centered = values.map { $0 - mean }

        // Compute variance
        let variance = centered.map { $0 * $0 }.reduce(0, +) / Double(n)
        guard variance > 1e-12 else {
            return .empty(signal: signal)
        }

        // Build period grid (linearly spaced in period)
        let periodStep = (maxPeriod - minPeriod) / Double(numFreqs)
        var periods = [Double](repeating: 0, count: numFreqs)
        var powerSpectrum = [Double](repeating: 0, count: numFreqs)

        for i in 0..<numFreqs {
            let period = minPeriod + Double(i) * periodStep
            periods[i] = period
            let omega = 2.0 * Double.pi / period

            // Compute tau offset: tan(2ωτ) = Σsin(2ωt) / Σcos(2ωt)
            var sin2Sum = 0.0
            var cos2Sum = 0.0
            for j in 0..<n {
                let arg = 2.0 * omega * times[j]
                sin2Sum += sin(arg)
                cos2Sum += cos(arg)
            }
            let tau = atan2(sin2Sum, cos2Sum) / (2.0 * omega)

            // Compute power components
            var cosSum = 0.0
            var sinSum = 0.0
            var cos2Norm = 0.0
            var sin2Norm = 0.0

            for j in 0..<n {
                let arg = omega * (times[j] - tau)
                let c = cos(arg)
                let s = sin(arg)
                cosSum += centered[j] * c
                sinSum += centered[j] * s
                cos2Norm += c * c
                sin2Norm += s * s
            }

            // Avoid division by zero
            let cosTerm = cos2Norm > 1e-12 ? (cosSum * cosSum) / cos2Norm : 0
            let sinTerm = sin2Norm > 1e-12 ? (sinSum * sinSum) / sin2Norm : 0

            powerSpectrum[i] = (cosTerm + sinTerm) / (2.0 * variance)
        }

        // Significance threshold: Bonferroni-corrected for M_eff independent frequencies.
        // M_eff = N/2 (effective number of independent frequencies, per Scargle 1982),
        // NOT numFreqs (which is just grid resolution for visual smoothness).
        // FAP = 1 - (1 - e^(-z))^M_eff = 0.01  →  z = -ln(1 - (1-0.01)^(1/M_eff))
        let mEff = max(Double(n) / 2.0, 1.0)
        let pSingle = 1.0 - pow(1.0 - 0.01, 1.0 / mEff)
        let threshold = pSingle > 0 ? -log(pSingle) : 0

        // Peak detection: local maxima above threshold
        let peaks = detectPeaks(periods: periods, power: powerSpectrum, threshold: threshold)

        return PeriodogramResult(
            signal: signal,
            periods: periods,
            power: powerSpectrum,
            significanceThreshold: threshold,
            peaks: peaks
        )
    }

    // MARK: - Peak Detection

    /// Known biological periods and their tolerance windows (hours).
    private static let knownPeriods: [(label: PeakLabel, center: Double, tolerance: Double)] = [
        (.circadian, 24, 2),
        (.weekly, 168, 12),
        (.biweekly, 336, 24),
        (.menstrual, 672, 48),
    ]

    /// Detect local maxima in the power spectrum that exceed the significance threshold.
    private static func detectPeaks(periods: [Double], power: [Double], threshold: Double) -> [Peak] {
        guard periods.count >= 3 else { return [] }

        var peaks: [Peak] = []

        for i in 1..<(periods.count - 1) {
            // Local maximum check
            guard power[i] > power[i - 1] && power[i] > power[i + 1] else { continue }
            // Above significance threshold
            guard power[i] > threshold else { continue }

            let label = labelForPeriod(periods[i])
            peaks.append(Peak(period: periods[i], power: power[i], label: label))
        }

        // Sort by power descending
        peaks.sort { $0.power > $1.power }

        return peaks
    }

    /// Assign a biological label if the period is near a known rhythm.
    private static func labelForPeriod(_ period: Double) -> PeakLabel? {
        for known in knownPeriods {
            if abs(period - known.center) <= known.tolerance {
                return known.label
            }
        }
        return nil
    }

    // MARK: - Signal Extraction

    /// Convenience method: extract signal from sleep records and compute periodogram.
    ///
    /// - Parameters:
    ///   - records: Array of SleepRecord sorted by day.
    ///   - signal: Which signal to analyze.
    ///   - healthProfiles: Optional health profiles for HR/HRV signals.
    /// - Returns: PeriodogramResult for the requested signal.
    public static func analyze(
        _ records: [SleepRecord],
        signal: Signal,
        healthProfiles: [DayHealthProfile] = []
    ) -> PeriodogramResult {
        let extracted: (times: [Double], values: [Double])

        switch signal {
        case .sleepMidpoint:
            extracted = extractSleepMidpoint(from: records)
        case .sleepDuration:
            extracted = extractSleepDuration(from: records)
        case .cosinorAmplitude:
            extracted = extractCosinorAmplitude(from: records)
        case .restingHR:
            extracted = extractHealthSignal(from: healthProfiles, keyPath: \.restingHR)
        case .nocturnalHRV:
            extracted = extractHealthSignal(from: healthProfiles, keyPath: \.avgNocturnalHRV)
        }

        // maxPeriod = half the data span (need ≥2 full cycles to confirm a rhythm)
        let span = (extracted.times.last ?? 0) - (extracted.times.first ?? 0)
        let adaptiveMaxPeriod = max(span / 2.0, 24.0) // at least 24h

        return compute(times: extracted.times, values: extracted.values, signal: signal,
                       maxPeriod: adaptiveMaxPeriod)
    }

    /// Run periodogram analysis on all available signals.
    ///
    /// Skips restingHR and nocturnalHRV if fewer than 14 non-nil health profiles are available.
    ///
    /// - Parameters:
    ///   - records: Array of SleepRecord sorted by day.
    ///   - healthProfiles: Optional health profiles for HR/HRV signals.
    /// - Returns: Dictionary mapping each analyzed signal to its result.
    public static func analyzeAll(
        _ records: [SleepRecord],
        healthProfiles: [DayHealthProfile] = []
    ) -> [Signal: PeriodogramResult] {
        var results: [Signal: PeriodogramResult] = [:]

        // Always analyze sleep-derived signals
        let sleepSignals: [Signal] = [.sleepMidpoint, .sleepDuration, .cosinorAmplitude]
        for signal in sleepSignals {
            results[signal] = analyze(records, signal: signal, healthProfiles: healthProfiles)
        }

        // Only analyze health signals if enough non-nil data is available
        let hrCount = healthProfiles.filter { $0.restingHR != nil }.count
        let hrvCount = healthProfiles.filter { $0.avgNocturnalHRV != nil }.count

        if hrCount >= minimumDataPoints {
            results[.restingHR] = analyze(records, signal: .restingHR, healthProfiles: healthProfiles)
        }
        if hrvCount >= minimumDataPoints {
            results[.nocturnalHRV] = analyze(records, signal: .nocturnalHRV, healthProfiles: healthProfiles)
        }

        return results
    }

    // MARK: - Private Extraction Methods

    /// Extract sleep midpoint times with circular-aware phase unwrapping.
    ///
    /// Midpoint of a sleep session crossing midnight (e.g. bedtime 23, wake 7)
    /// is computed by unwrapping: 23→25 (i.e. bedtime + 24-gap accounted),
    /// midpoint = (23 + 31)/2 = 27, then mod 24 = 3 (3 AM).
    ///
    /// For the time series, we unwrap the midpoint sequence to preserve drift
    /// (avoiding 23→1 jumps that look like discontinuities).
    private static func extractSleepMidpoint(from records: [SleepRecord]) -> (times: [Double], values: [Double]) {
        guard !records.isEmpty else { return ([], []) }

        var times: [Double] = []
        var values: [Double] = []

        var previousMidpoint: Double? = nil

        for record in records {
            let bedtime = record.bedtimeHour
            var wake = record.wakeupHour

            // If wake < bedtime, the sleep crosses midnight
            if wake < bedtime {
                wake += 24.0
            }

            var midpoint = (bedtime + wake) / 2.0
            // Normalize to [0, 24)
            midpoint = midpoint.truncatingRemainder(dividingBy: 24.0)
            if midpoint < 0 { midpoint += 24.0 }

            // Unwrap relative to previous midpoint to preserve drift
            if let prev = previousMidpoint {
                var diff = midpoint - prev
                if diff > 12.0 { diff -= 24.0 }
                if diff < -12.0 { diff += 24.0 }
                midpoint = prev + diff
            }

            previousMidpoint = midpoint
            times.append(Double(record.day) * 24.0) // time in hours
            values.append(midpoint)
        }

        return (times, values)
    }

    /// Extract sleep duration as a simple time series.
    private static func extractSleepDuration(from records: [SleepRecord]) -> (times: [Double], values: [Double]) {
        let times = records.map { Double($0.day) * 24.0 }
        let values = records.map { $0.sleepDuration }
        return (times, values)
    }

    /// Extract cosinor amplitude as a time series.
    private static func extractCosinorAmplitude(from records: [SleepRecord]) -> (times: [Double], values: [Double]) {
        let times = records.map { Double($0.day) * 24.0 }
        let values = records.map { $0.cosinor.amplitude }
        return (times, values)
    }

    /// Extract a health signal (restingHR or nocturnalHRV), skipping days with nil values.
    private static func extractHealthSignal(
        from profiles: [DayHealthProfile],
        keyPath: KeyPath<DayHealthProfile, Double?>
    ) -> (times: [Double], values: [Double]) {
        var times: [Double] = []
        var values: [Double] = []

        for profile in profiles {
            if let value = profile[keyPath: keyPath] {
                times.append(Double(profile.day) * 24.0)
                values.append(value)
            }
        }

        return (times, values)
    }
}
