import Foundation

// MARK: - Output Types

/// The measured impact of a single event type on nightly fragmentation.
public struct EventImpact: Codable, Sendable {
    /// The circadian event category.
    public let eventType: EventType
    /// α — how much this event type raises the awakening rate λ.
    public let excitationStrength: Double
    /// Mean delay from event occurrence to peak fragmentation effect, in hours.
    public let delayHours: Double
    /// True when excitationStrength > 0.1 (considered practically significant).
    public let significantEffect: Bool

    public init(
        eventType: EventType,
        excitationStrength: Double,
        delayHours: Double,
        significantEffect: Bool
    ) {
        self.eventType = eventType
        self.excitationStrength = excitationStrength
        self.delayHours = delayHours
        self.significantEffect = significantEffect
    }
}

/// Full output of the Hawkes-process event impact analysis.
public struct HawkesAnalysisResult: Codable, Sendable {
    /// μ — estimated base awakening rate without any event excitation.
    public let baseIntensity: Double
    /// Per event-type excitation parameters.
    public let eventImpacts: [EventImpact]
    /// Half-life of the exponential decay kernel that gave the best R² fit (hours).
    public let decayHalfLife: Double

    public init(
        baseIntensity: Double,
        eventImpacts: [EventImpact],
        decayHalfLife: Double
    ) {
        self.baseIntensity = baseIntensity
        self.eventImpacts = eventImpacts
        self.decayHalfLife = decayHalfLife
    }
}

// MARK: - Main Analyzer

/// Models how contextual circadian events affect nightly sleep fragmentation
/// using a simplified Hawkes self-exciting process.
///
/// The intensity model is:
/// ```
/// λ(night) = μ + Σ_type α_type · Σ_events_of_type exp(-(night_start - t_event) / halfLife)
/// ```
/// Parameters (μ, α, halfLife) are estimated by ordinary least squares regression
/// over a grid of candidate half-lives {12, 24, 36, 48, 72} hours.
public enum HawkesEventModel {

    private static let candidateHalfLives: [Double] = [12, 24, 36, 48, 72]

    /// Estimate Hawkes parameters from sleep records and circadian events.
    ///
    /// - Parameters:
    ///   - records: Sleep records (any order, >= 1 record needed for a result).
    ///   - events:  All circadian events. May be empty.
    /// - Returns: A ``HawkesAnalysisResult`` with base intensity, per-type excitation
    ///   strengths, and the best-fit decay half-life.
    public static func analyze(
        records: [SleepRecord],
        events: [CircadianEvent]
    ) -> HawkesAnalysisResult {
        let sorted = records.sorted { $0.day < $1.day }
        let allTypes = EventType.allCases

        // Awakening counts per night
        let awakeCounts = sorted.map { countAwakenings(record: $0) }
        let y = awakeCounts.map(Double.init)

        guard !y.isEmpty else {
            return HawkesAnalysisResult(baseIntensity: 0, eventImpacts: [], decayHalfLife: 24)
        }

        // If no events, return mean as base intensity with no excitation
        guard !events.isEmpty else {
            let mu = y.reduce(0, +) / Double(y.count)
            return HawkesAnalysisResult(
                baseIntensity: mu,
                eventImpacts: [],
                decayHalfLife: 24
            )
        }

        // Grid search over half-lives
        var bestHalfLife = candidateHalfLives[0]
        var bestR2 = -Double.infinity
        var bestResult: HawkesAnalysisResult?

        for halfLife in candidateHalfLives {
            if let result = fitModel(sorted: sorted, events: events, y: y, halfLife: halfLife, types: allTypes) {
                if result.r2 > bestR2 {
                    bestR2 = result.r2
                    bestHalfLife = halfLife
                    bestResult = result.profile
                }
            }
        }

        return bestResult ?? fallbackResult(y: y, halfLife: bestHalfLife)
    }

    // MARK: - Model Fitting

    private struct FitResult {
        let profile: HawkesAnalysisResult
        let r2: Double
    }

    /// Build the excitation design matrix and fit via OLS.
    ///
    /// Returns nil when the system is degenerate (e.g., all excitations are zero).
    private static func fitModel(
        sorted: [SleepRecord],
        events: [CircadianEvent],
        y: [Double],
        halfLife: Double,
        types: [EventType]
    ) -> FitResult? {
        let n = sorted.count

        // For each night, compute excitation sum per event type
        // excitation_type[night] = Σ_{events of type} exp(-(night_start - event_absoluteHour) / halfLife)
        var excitationMatrix: [[Double]] = []  // [type][night]
        var usedTypes: [EventType] = []

        for type_ in types {
            let typeEvents = events.filter { $0.type == type_ }
            guard !typeEvents.isEmpty else { continue }

            var exc = [Double](repeating: 0.0, count: n)
            for (nightIdx, record) in sorted.enumerated() {
                let nightStart = Double(record.day) * 24.0 + record.bedtimeHour
                var sum = 0.0
                for event in typeEvents {
                    let delay = nightStart - event.absoluteHour
                    if delay > 0 {
                        sum += exp(-delay / halfLife)
                    }
                }
                exc[nightIdx] = sum
            }
            excitationMatrix.append(exc)
            usedTypes.append(type_)
        }

        // If no type has any effect, return nil
        let hasAnyExcitation = excitationMatrix.contains { $0.contains { $0 > 0 } }
        guard hasAnyExcitation else { return nil }

        // Fit: for each event type independently, do simple linear regression
        // awakenings ~ μ + α * excitation_type
        // Then combine: μ = mean(y) - Σ α * mean(excitation_type)
        var alphas = [Double](repeating: 0.0, count: usedTypes.count)
        let yMean = y.reduce(0, +) / Double(n)

        for (i, exc) in excitationMatrix.enumerated() {
            let (_, slope, _) = linearRegression(x: exc, y: y)
            alphas[i] = slope  // positive = worsens sleep, negative = improves sleep
        }

        // Base intensity: μ = yMean - Σ α_i * mean(exc_i)
        var mu = yMean
        for (i, exc) in excitationMatrix.enumerated() {
            let excMean = exc.reduce(0, +) / Double(n)
            mu -= alphas[i] * excMean
        }
        mu = max(0.0, mu)

        // Compute R² of the full model
        var yHat = [Double](repeating: mu, count: n)
        for (i, exc) in excitationMatrix.enumerated() {
            for j in 0..<n {
                yHat[j] += alphas[i] * exc[j]
            }
        }
        let r2 = computeR2(y: y, yHat: yHat)

        // Build EventImpact list
        let impacts: [EventImpact] = usedTypes.enumerated().map { (i, type_) in
            EventImpact(
                eventType: type_,
                excitationStrength: alphas[i],
                delayHours: halfLife,  // halfLife is the characteristic delay
                significantEffect: abs(alphas[i]) > 0.1
            )
        }

        let profile = HawkesAnalysisResult(
            baseIntensity: mu,
            eventImpacts: impacts,
            decayHalfLife: halfLife
        )
        return FitResult(profile: profile, r2: r2)
    }

    // MARK: - Fallback

    private static func fallbackResult(y: [Double], halfLife: Double) -> HawkesAnalysisResult {
        let mu = y.isEmpty ? 0.0 : y.reduce(0, +) / Double(y.count)
        return HawkesAnalysisResult(baseIntensity: mu, eventImpacts: [], decayHalfLife: halfLife)
    }

    // MARK: - Awakening Counter

    private static func countAwakenings(record: SleepRecord) -> Int {
        let bedtime = record.bedtimeHour
        let wakeup  = record.wakeupHour
        return record.phases.filter { interval in
            guard interval.phase == .awake else { return false }
            let h = interval.hour
            if bedtime <= wakeup {
                return h >= bedtime && h < wakeup
            } else {
                return h >= bedtime || h < wakeup
            }
        }.count
    }

    // MARK: - Statistics Helpers

    /// Simple OLS: y = intercept + slope * x.
    ///
    /// Returns (intercept, slope, R²).
    static func linearRegression(x: [Double], y: [Double]) -> (Double, Double, Double) {
        let n = x.count
        guard n >= 2 else { return (y.first ?? 0, 0, 0) }

        let xMean = x.reduce(0, +) / Double(n)
        let yMean = y.reduce(0, +) / Double(n)

        var ssXY = 0.0
        var ssXX = 0.0
        for i in 0..<n {
            ssXY += (x[i] - xMean) * (y[i] - yMean)
            ssXX += (x[i] - xMean) * (x[i] - xMean)
        }

        guard ssXX > 1e-12 else { return (yMean, 0, 0) }

        let slope = ssXY / ssXX
        let intercept = yMean - slope * xMean
        let yHat = x.map { intercept + slope * $0 }
        let r2 = computeR2(y: y, yHat: yHat)
        return (intercept, slope, r2)
    }

    private static func computeR2(y: [Double], yHat: [Double]) -> Double {
        let n = y.count
        guard n >= 2 else { return 0 }
        let yMean = y.reduce(0, +) / Double(n)
        let ssTot = y.reduce(0) { $0 + ($1 - yMean) * ($1 - yMean) }
        guard ssTot > 1e-12 else { return 1.0 }
        let ssRes = zip(y, yHat).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        return max(0.0, 1.0 - ssRes / ssTot)
    }
}
