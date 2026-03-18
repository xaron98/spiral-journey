#if canImport(Accelerate)
import Accelerate
#endif
import Foundation

/// Synchrony measurement between a strand-1 (sleep) and strand-2 (context) feature pair.
public struct BasePairSynchrony: Codable, Sendable {
    /// Strand-1 feature index (0-7).
    public let sleepFeatureIndex: Int
    /// Strand-2 feature index (8-15).
    public let contextFeatureIndex: Int
    /// Phase Locking Value in [0, 1].
    public let plv: Double
    /// Mean phase difference in radians.
    public let meanPhaseDiff: Double
    /// Detected lag in days (0 for now).
    public let lagDays: Int
}

/// Computes Phase Locking Value (PLV) between strand-1 and strand-2 features
/// using the Hilbert Transform (FFT-based via Accelerate).
public enum HilbertPhaseAnalyzer {

    /// Minimum signal length required for meaningful FFT-based phase analysis.
    private static let minimumLength = 4

    /// PLV threshold below which pairs are considered non-synchronous and filtered out.
    private static let significanceThreshold = 0.3

    /// Compute PLV between all strand1 x strand2 pairs over a rolling window.
    ///
    /// - Parameters:
    ///   - nucleotides: The full set of day nucleotides (sorted by day internally).
    ///   - windowSize: Number of recent days to analyze (default 14).
    /// - Returns: Pairs with PLV > 0.3, sorted by PLV descending.
    public static func analyze(
        nucleotides: [DayNucleotide],
        windowSize: Int = 14
    ) -> [BasePairSynchrony] {
        let sorted = nucleotides.sorted { $0.day < $1.day }
        let window = Array(sorted.suffix(windowSize))

        guard window.count >= minimumLength else { return [] }

        var results: [BasePairSynchrony] = []

        // 8 strand-1 features (indices 0-7) x 8 strand-2 features (indices 8-15) = 64 pairs
        for s1 in 0..<8 {
            let series1 = window.map { $0.features[s1] }
            let phase1 = instantaneousPhase(series1)
            guard let phase1 else { continue }

            for s2 in 8..<16 {
                let series2 = window.map { $0.features[s2] }
                let phase2 = instantaneousPhase(series2)
                guard let phase2 else { continue }

                let (plv, meanDiff) = computePLV(phase1: phase1, phase2: phase2)

                if plv > significanceThreshold {
                    results.append(BasePairSynchrony(
                        sleepFeatureIndex: s1,
                        contextFeatureIndex: s2,
                        plv: plv,
                        meanPhaseDiff: meanDiff,
                        lagDays: 0
                    ))
                }
            }
        }

        return results.sorted { $0.plv > $1.plv }
    }

    // MARK: - Hilbert Transform

    #if canImport(Accelerate)
    /// Compute instantaneous phase via the Hilbert Transform using Accelerate FFT.
    ///
    /// Algorithm:
    /// 1. Forward complex FFT of the (real) signal
    /// 2. Zero out negative frequencies, double positive frequencies (keep DC and Nyquist)
    /// 3. Inverse complex FFT -> analytic signal (complex)
    /// 4. atan2(imaginary, real) -> instantaneous phase
    static func instantaneousPhase(_ signal: [Double]) -> [Double]? {
        let n = signal.count
        guard n >= minimumLength else { return nil }

        // Check for constant signal (zero variance) -- phase is undefined
        var mean = 0.0
        vDSP_meanvD(signal, 1, &mean, vDSP_Length(n))
        let centered = signal.map { $0 - mean }
        var variance = 0.0
        vDSP_dotprD(centered, 1, centered, 1, &variance, vDSP_Length(n))
        if variance / Double(n) < 1e-14 { return nil }

        // Use power-of-2 length for FFT
        let fftLength = nextPowerOfTwo(n)
        let log2n = vDSP_Length(log2(Double(fftLength)))

        guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        // Prepare split complex buffers for complex FFT (full length)
        var realp = [Double](repeating: 0, count: fftLength)
        var imagp = [Double](repeating: 0, count: fftLength)

        // Copy signal into real part (zero-padded), imaginary stays zero
        for i in 0..<n {
            realp[i] = signal[i]
        }

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPDoubleSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Forward complex FFT
                vDSP_fft_zipD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Apply Hilbert transform in frequency domain:
                // For a signal of length N:
                //   k = 0 (DC): keep as is
                //   k = 1..<N/2 (positive freq): multiply by 2
                //   k = N/2 (Nyquist): keep as is
                //   k = N/2+1..<N (negative freq): zero out
                let halfLen = fftLength / 2

                // Double positive frequencies (k = 1..<halfLen)
                for k in 1..<halfLen {
                    realBuf[k] *= 2.0
                    imagBuf[k] *= 2.0
                }

                // Zero out negative frequencies (k = halfLen+1..<fftLength)
                for k in (halfLen + 1)..<fftLength {
                    realBuf[k] = 0.0
                    imagBuf[k] = 0.0
                }

                // Inverse complex FFT
                vDSP_fft_zipD(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))
            }
        }

        // vDSP complex FFT does not normalize; divide by fftLength
        let scale = 1.0 / Double(fftLength)

        var phases = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let re = realp[i] * scale
            let im = imagp[i] * scale
            phases[i] = atan2(im, re)
        }

        return phases
    }

    #else
    /// Fallback: Compute instantaneous phase via a naive DFT-based Hilbert Transform.
    /// Used on platforms where Accelerate is unavailable (e.g. Linux).
    static func instantaneousPhase(_ signal: [Double]) -> [Double]? {
        let n = signal.count
        guard n >= minimumLength else { return nil }

        // Check for constant signal (zero variance) -- phase is undefined
        let mean = signal.reduce(0, +) / Double(n)
        let centered = signal.map { $0 - mean }
        let variance = centered.reduce(0) { $0 + $1 * $1 } / Double(n)
        if variance < 1e-14 { return nil }

        // Forward DFT: X[k] = sum_{t=0}^{N-1} x[t] * exp(-i * 2pi * k * t / N)
        var freqReal = [Double](repeating: 0, count: n)
        var freqImag = [Double](repeating: 0, count: n)
        for k in 0..<n {
            var sumR = 0.0, sumI = 0.0
            for t in 0..<n {
                let angle = -2.0 * .pi * Double(k) * Double(t) / Double(n)
                sumR += signal[t] * cos(angle)
                sumI += signal[t] * sin(angle)
            }
            freqReal[k] = sumR
            freqImag[k] = sumI
        }

        // Apply Hilbert transform in frequency domain
        let halfLen = n / 2
        // DC (k=0): keep as is
        // Positive frequencies (k = 1..<halfLen): multiply by 2
        for k in 1..<halfLen {
            freqReal[k] *= 2.0
            freqImag[k] *= 2.0
        }
        // Nyquist (k = halfLen): keep as is (only for even n)
        // Negative frequencies: zero out
        for k in (halfLen + 1)..<n {
            freqReal[k] = 0.0
            freqImag[k] = 0.0
        }

        // Inverse DFT: x[t] = (1/N) * sum_{k=0}^{N-1} X[k] * exp(+i * 2pi * k * t / N)
        let scale = 1.0 / Double(n)
        var phases = [Double](repeating: 0, count: n)
        for t in 0..<n {
            var sumR = 0.0, sumI = 0.0
            for k in 0..<n {
                let angle = 2.0 * .pi * Double(k) * Double(t) / Double(n)
                sumR += freqReal[k] * cos(angle) - freqImag[k] * sin(angle)
                sumI += freqReal[k] * sin(angle) + freqImag[k] * cos(angle)
            }
            let re = sumR * scale
            let im = sumI * scale
            phases[t] = atan2(im, re)
        }

        return phases
    }
    #endif

    // MARK: - PLV Computation

    /// Compute Phase Locking Value and mean phase difference.
    ///
    /// PLV = |mean(exp(i * delta_theta))| where delta_theta = phase1 - phase2
    static func computePLV(phase1: [Double], phase2: [Double]) -> (plv: Double, meanPhaseDiff: Double) {
        let n = min(phase1.count, phase2.count)
        guard n > 0 else { return (0, 0) }

        var sumCos = 0.0
        var sumSin = 0.0

        for i in 0..<n {
            let diff = phase1[i] - phase2[i]
            sumCos += cos(diff)
            sumSin += sin(diff)
        }

        let meanCos = sumCos / Double(n)
        let meanSin = sumSin / Double(n)
        let plv = sqrt(meanCos * meanCos + meanSin * meanSin)
        let meanPhaseDiff = atan2(meanSin, meanCos)

        return (plv, meanPhaseDiff)
    }

    // MARK: - Helpers

    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var v = 1
        while v < n {
            v *= 2
        }
        return v
    }
}
