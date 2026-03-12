import Foundation

/// Computes the SpiralConsistencyScore from an array of SleepRecords.
///
/// All calculations are purely statistical on the timing and structural data
/// already present in SleepRecord (bedtimeHour, wakeupHour, sleepDuration,
/// hourlyActivity, cosinor). No medical claims are made.
///
/// recoveryStability uses cosinor R² as a proxy when no physiological data
/// (HRV/HR) is provided — the architecture accepts optional recovery values
/// and redistributes weights automatically if they are absent.
public enum SpiralConsistencyCalculator {

    // MARK: - Public API

    /// Compute consistency over a sliding window of up to `windowDays` nights.
    /// Pass `recoveryValues` if you have per-night HRV or resting-HR data
    /// (same-indexed as the tail of `records`); otherwise pass nil/empty.
    public static func compute(
        records: [SleepRecord],
        windowDays: Int = 7,
        recoveryValues: [Double]? = nil   // optional per-night 0-1 physiological recovery
    ) -> SpiralConsistencyScore {

        guard records.count >= 2 else {
            return SpiralConsistencyScore(confidence: .low)
        }

        // Use only records that represent a real night (≥ 3h) to exclude
        // same-episode "stub" records produced when an episode crosses midnight:
        // ManualDataConverter assigns the same episode to both the sleep-start day
        // (small fragment, e.g. 1h) and the wake-up day (full night, e.g. 7h).
        // Including stubs inflates nightsUsed and corrupts bedtime/wakeup metrics.
        let withData = records.filter { $0.sleepDuration >= 3.0 }
        let window   = Array(withData.suffix(windowDays))
        let n        = window.count

        guard n >= 2 else {
            return SpiralConsistencyScore(nightsUsed: n, confidence: .low)
        }

        // ── Sub-metrics ────────────────────────────────────────────────────

        let onsetScore       = sleepOnsetRegularity(window)
        let wakeScore        = wakeTimeRegularity(window)
        let fragScore        = fragmentationSimilarity(window)
        let durationScore    = durationStability(window)
        let (recovScore, realData) = recoveryStabilityScore(window, external: recoveryValues)

        // ── Weight redistribution if recovery is absent ───────────────────
        // Default: onset 30%, wake 25%, frag 25%, duration 10%, recovery 10%
        let hasRecovery = recovScore > 0 || realData
        let w: (onset: Double, wake: Double, frag: Double, dur: Double, rec: Double)
        if hasRecovery {
            w = (0.30, 0.25, 0.25, 0.10, 0.10)
        } else {
            // redistribute recovery weight equally among the four main metrics
            w = (0.3375, 0.28125, 0.28125, 0.1125, 0.0)
        }

        let rawScore = onsetScore    * w.onset
                     + wakeScore    * w.wake
                     + fragScore    * w.frag
                     + durationScore * w.dur
                     + recovScore   * w.rec

        let finalScore = Int(clamp(rawScore, 0, 100).rounded())

        let breakdown = ConsistencyBreakdown(
            sleepOnsetRegularity:           onsetScore,
            wakeTimeRegularity:             wakeScore,
            fragmentationPatternSimilarity: fragScore,
            sleepDurationStability:         durationScore,
            recoveryStability:              recovScore,
            recoveryFromRealData:           realData
        )

        let confidence: ConfidenceLevel = n >= 7 ? .high : (n >= 4 ? .medium : .low)

        // ── Disruption detection ───────────────────────────────────────────
        let (insights, localDays, globalDays) = detectDisruptions(window)

        // ── Delta vs previous window ───────────────────────────────────────
        var delta: Double? = nil
        if withData.count >= windowDays * 2 {
            let prev = Array(withData.dropLast(windowDays).suffix(windowDays))
            if prev.count >= 2 {
                let prevOnset    = sleepOnsetRegularity(prev)
                let prevWake     = wakeTimeRegularity(prev)
                let prevFrag     = fragmentationSimilarity(prev)
                let prevDur      = durationStability(prev)
                let (prevRec, _) = recoveryStabilityScore(prev, external: nil)
                let prevRaw = prevOnset * w.onset + prevWake * w.wake
                            + prevFrag * w.frag + prevDur * w.dur + prevRec * w.rec
                delta = rawScore - clamp(prevRaw, 0, 100)
            }
        }

        return SpiralConsistencyScore(
            score:               finalScore,
            label:               ConsistencyLabel.from(score: finalScore),
            breakdown:           breakdown,
            deltaVsPreviousWeek: delta,
            nightsUsed:          n,
            confidence:          confidence,
            insights:            insights,
            localDisruptionDays: localDays,
            globalShiftDays:     globalDays
        )
    }

    // MARK: - Sub-metrics

    /// Regularity of sleep-onset clock hour (0-100).
    /// Mean absolute deviation from the circular mean, penalised for shifts > 45 min.
    /// Uses raw clock hours (0–24) without normalization so that any sleep schedule
    /// (nocturnal, diurnal, shifted) is handled correctly by circular arithmetic.
    static func sleepOnsetRegularity(_ nights: [SleepRecord]) -> Double {
        let onsets = nights.map { $0.bedtimeHour }
        return circularTimeRegularity(onsets, penaltyThresholdHours: 0.75)
    }

    /// Regularity of wake-time clock hour (0-100).
    /// Uses linear SD (not circular) because wake times cluster in the morning
    /// and don't wrap around midnight, so circular arithmetic is not needed.
    static func wakeTimeRegularity(_ nights: [SleepRecord]) -> Double {
        // Filter out 0.0 which is an artefact of episode.end % 24 when end lands exactly on midnight
        let wakes = nights.map { $0.wakeupHour }.filter { $0 > 0 }
        guard wakes.count >= 2 else { return 100 }
        let mu  = mean(wakes)
        let sd  = standardDeviation(wakes)
        // SD=0 → 100, SD=5h → 0 (wide range: real-world inconsistent schedules can have 3-4h SD)
        let baseScore = clamp((1 - sd / 5.0) * 100, 0, 100)
        let penaltyCount = wakes.filter { abs($0 - mu) > 1.0 }.count
        let penaltyFraction = Double(penaltyCount) / Double(wakes.count)
        return clamp(baseScore - penaltyFraction * 25, 0, 100)
    }

    /// Similarity of the hourly fragmentation pattern using cosine similarity (0-100).
    /// Each night is represented as a 24-dim vector where entry h =
    /// fraction of that hour spent awake (from hourlyActivity).
    static func fragmentationSimilarity(_ nights: [SleepRecord]) -> Double {
        let vectors = nights.map { awakeVector($0) }
        guard vectors.count >= 2 else { return 100 }

        // mean vector = baseline
        let mean = meanVector(vectors)

        // average cosine similarity of each night against the mean
        let sims = vectors.map { cosineSimilarity($0, mean) }
        let avg  = sims.reduce(0, +) / Double(sims.count)

        // cosine similarity in [0,1] → scale to 0-100
        return clamp(avg * 100, 0, 100)
    }

    /// Stability of total sleep duration via coefficient of variation (0-100).
    static func durationStability(_ nights: [SleepRecord]) -> Double {
        let durations = nights.map { $0.sleepDuration }.filter { $0 > 0 }
        guard durations.count >= 2 else { return 100 }
        let mu  = mean(durations)
        guard mu > 0.1 else { return 50 }
        let cv  = standardDeviation(durations) / mu   // 0 = perfect, 1 = high variation
        // cv = 0 → 100, cv = 0.5 → 0 (very unstable)
        return clamp((1 - cv / 0.5) * 100, 0, 100)
    }

    /// Recovery stability using cosinor R² as proxy, or external values if provided.
    /// Returns (score 0-100, isRealData).
    static func recoveryStabilityScore(_ nights: [SleepRecord], external: [Double]?) -> (Double, Bool) {
        // If external physiological values provided (HRV or resting HR normalised 0-1)
        if let ext = external, ext.count >= 2 {
            let sigma = standardDeviation(ext)
            // sigma = 0 → 100, sigma = 0.3 → 0
            return (clamp((1 - sigma / 0.3) * 100, 0, 100), true)
        }
        // Fallback: use cosinor R² stability across nights
        let r2s = nights.map { $0.cosinor.r2 }.filter { $0.isFinite }
        guard r2s.count >= 2 else { return (0, false) }
        let sigma = standardDeviation(r2s)
        return (clamp((1 - sigma / 0.4) * 100, 0, 100), false)
    }

    // MARK: - Disruption Detection

    /// Returns (insights, localDisruptionDays, globalShiftDays).
    static func detectDisruptions(_ nights: [SleepRecord]) -> ([PatternInsight], [Int], [Int]) {
        guard nights.count >= 3 else { return ([], [], []) }

        var insights: [PatternInsight] = []
        var localDays: [Int] = []
        var globalDays: [Int] = []

        let onsets = nights.map { $0.bedtimeHour }
        let wakes  = nights.map { $0.wakeupHour }
        let meanOnset = circularMean(onsets)
        let meanWake  = mean(wakes)
        let sdOnset   = circularSD(onsets)
        for (_, night) in nights.enumerated() {
            let dayIdx = night.day
            let onsetDiff = abs(circularDiff(night.bedtimeHour, meanOnset))
            let wakeDiff  = abs(night.wakeupHour - meanWake)

            // ── Global shift: both onset AND wake deviate significantly ───
            let globalThresholdH = max(1.5, sdOnset * 2.0)
            if onsetDiff > globalThresholdH && wakeDiff > globalThresholdH * 0.8 {
                globalDays.append(dayIdx)
                let dir = circularDiff(night.bedtimeHour, meanOnset) > 0 ? "más tarde" : "más temprano"
                insights.append(PatternInsight(
                    type: .global,
                    title: "Desplazamiento global del sueño",
                    summary: String(format: "Esta noche tu patrón se desplazó %.0f min %@",
                                   onsetDiff * 60, dir),
                    severity: onsetDiff > 2 ? 2 : 1,
                    recommendedAction: "Intenta mantener una hora de inicio y despertar estable, incluso en fines de semana."
                ))
                continue
            }

            // ── Local disruption: fragmentation concentrated in ≤25% of night arc ─
            let awakeVec = awakeVector(night)
            // Find contiguous awake bins
            let localBins = contiguousAwakeBins(awakeVec, threshold: 0.4)
            if let widest = localBins.max(by: { $0.count < $1.count }) {
                let binFraction = Double(widest.count) / 24.0
                let totalAwakeFraction = awakeVec.filter { $0 > 0.4 }.count
                if binFraction <= 0.25 && Double(totalAwakeFraction) / 24 > 0.08 {
                    let startH = Double(widest.first ?? 0)
                    let endH   = Double((widest.last ?? 0) + 1)
                    localDays.append(dayIdx)
                    insights.append(PatternInsight(
                        type: .local,
                        title: "Disrupción localizada",
                        summary: String(format: "Despertares concentrados alrededor de las %02.0f:00–%02.0f:00",
                                        startH, endH),
                        severity: 1,
                        affectedStart: startH,
                        affectedEnd: endH,
                        recommendedAction: "Revisa temperatura, ruido o luz en esa franja. Considera reducir líquidos por la tarde."
                    ))
                }
            }

            // ── Mixed: both local fragmentation AND onset deviation ────────
            if localDays.contains(dayIdx) && onsetDiff > sdOnset * 1.5 {
                // Upgrade last local insight to mixed
                if let last = insights.indices.last, insights[last].type == .local {
                    insights[last] = PatternInsight(
                        type: .mixed,
                        title: "Disrupción mixta",
                        summary: insights[last].summary + " con desplazamiento de inicio de sueño",
                        severity: 2,
                        affectedStart: insights[last].affectedStart,
                        affectedEnd: insights[last].affectedEnd,
                        recommendedAction: insights[last].recommendedAction
                    )
                }
            }
        }

        // Sort by severity descending
        insights.sort { $0.severity > $1.severity }
        return (insights, localDays, globalDays)
    }

    // MARK: - Math Helpers

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v.isFinite ? v : lo))
    }

    private static func mean(_ v: [Double]) -> Double {
        v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    private static func standardDeviation(_ v: [Double]) -> Double {
        guard v.count >= 2 else { return 0 }
        let mu  = mean(v)
        let variance = v.map { ($0 - mu) * ($0 - mu) }.reduce(0, +) / Double(v.count)
        return sqrt(variance)
    }

    /// Map late bedtime hours (< 6) to > 24 so the circular mean works.
    private static func normalizeHour(_ h: Double) -> Double {
        h < 6 ? h + 24 : h
    }

    /// Circular mean of hour values (handles wrap-around at 24).
    /// Returns a value in [0, 24).
    private static func circularMean(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let radians = hours.map { $0 / 24.0 * 2 * .pi }
        let sinMean = radians.map { sin($0) }.reduce(0, +) / Double(radians.count)
        let cosMean = radians.map { cos($0) }.reduce(0, +) / Double(radians.count)
        let angle   = atan2(sinMean, cosMean)
        return (angle / (2 * .pi) * 24 + 24).truncatingRemainder(dividingBy: 24)
    }

    /// Circular standard deviation in hours.
    private static func circularSD(_ hours: [Double]) -> Double {
        guard hours.count >= 2 else { return 0 }
        let mu   = circularMean(hours)
        let diffs = hours.map { circularDiff($0, mu) }
        return standardDeviation(diffs)
    }

    /// Signed circular difference in hours (result in -12...12).
    private static func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d >  12 { d -= 24 }
        while d < -12 { d += 24 }
        return d
    }

    /// Score 0-100 for time regularity across nights.
    /// Penalises nights that deviate > threshold (in hours) with a steeper drop.
    private static func circularTimeRegularity(_ hours: [Double], penaltyThresholdHours: Double) -> Double {
        guard hours.count >= 2 else { return 100 }
        let mu      = circularMean(hours)
        let absDiffs = hours.map { abs(circularDiff($0, mu)) }
        let madH    = mean(absDiffs)   // mean absolute deviation in hours

        // penalty: each night above threshold adds extra cost
        let penaltyCount = absDiffs.filter { $0 > penaltyThresholdHours }.count
        let penaltyFraction = Double(penaltyCount) / Double(hours.count)

        // Base score: 0 MAD = 100, 6h MAD = 0 (wide range: irregular schedules can span many hours)
        let baseScore = clamp((1 - madH / 6.0) * 100, 0, 100)
        // Apply penalty: each 10% of "bad nights" costs 4 points (max -40 at full penalty)
        let penaltyScore = baseScore - penaltyFraction * 40
        return clamp(penaltyScore, 0, 100)
    }

    // MARK: - Vector Helpers (fragmentation)

    /// Build a 24-dim awake-fraction vector from hourlyActivity.
    private static func awakeVector(_ record: SleepRecord) -> [Double] {
        var v = [Double](repeating: 0, count: 24)
        for entry in record.hourlyActivity {
            let h = min(max(entry.hour, 0), 23)
            // hourlyActivity: 0.05 = sleeping, 0.95 = awake → we want awake fraction
            v[h] = entry.activity
        }
        return v
    }

    private static func meanVector(_ vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        let dim = vectors[0].count
        var result = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<min(dim, v.count) { result[i] += v[i] }
        }
        return result.map { $0 / Double(vectors.count) }
    }

    /// Cosine similarity in [0,1] (0 = orthogonal, 1 = identical direction).
    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let dim = min(a.count, b.count)
        guard dim > 0 else { return 0 }
        let dot   = (0..<dim).map { a[$0] * b[$0] }.reduce(0, +)
        let normA = sqrt((0..<dim).map { a[$0] * a[$0] }.reduce(0, +))
        let normB = sqrt((0..<dim).map { b[$0] * b[$0] }.reduce(0, +))
        guard normA > 1e-9 && normB > 1e-9 else { return 1.0 }
        return clamp(dot / (normA * normB), 0, 1)
    }

    /// Find contiguous runs of awake bins (activity > threshold).
    private static func contiguousAwakeBins(_ vec: [Double], threshold: Double) -> [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []
        for (i, v) in vec.enumerated() {
            if v > threshold {
                current.append(i)
            } else {
                if !current.isEmpty { runs.append(current); current = [] }
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
