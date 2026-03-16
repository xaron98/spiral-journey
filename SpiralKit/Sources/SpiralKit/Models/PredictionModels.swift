import Foundation

// MARK: - Prediction Input (Feature Vector)

/// Feature vector for sleep prediction.
/// All numeric fields are Double for future Core ML compatibility.
public struct PredictionInput: Codable, Sendable {

    // Temporal encoding
    public var sinHour: Double              // sin(2π · currentHour / 24)
    public var cosHour: Double              // cos(2π · currentHour / 24)

    // Calendar
    public var isWeekend: Double            // 1.0 if today is weekend, 0.0 otherwise
    public var isTomorrowWeekend: Double    // 1.0 if target night falls on weekend

    // Rolling 7-day averages
    public var meanBedtime7d: Double        // circular mean of recent bedtimeHours
    public var meanWake7d: Double           // mean of recent wakeupHours
    public var stdBedtime7d: Double         // circular SD of bedtimeHours

    // Sleep pressure
    public var sleepDebt: Double            // meanSleepDuration − goalDuration (hours)
    public var lastSleepDuration: Double    // most recent SleepRecord.sleepDuration
    public var processS: Double             // current homeostatic sleep pressure (0-1)

    // Circadian rhythm (from CosinorResult)
    public var acrophase: Double            // latest cosinor acrophase (hours)
    public var cosinorR2: Double            // rhythm fit quality (0-1)

    // Events today (counts)
    public var exerciseToday: Double
    public var caffeineToday: Double
    public var melatoninToday: Double
    public var stressToday: Double
    public var alcoholToday: Double

    // Drift
    public var driftRate: Double            // recent acrophase drift (minutes/day)

    // Stability
    public var consistencyScore: Double     // 0-100 from SpiralConsistencyScore

    // Chronotype
    public var chronotypeShift: Double      // offset from intermediate in hours

    // Metadata
    public var dataCount: Int               // number of records used

    public init(
        sinHour: Double = 0, cosHour: Double = 0,
        isWeekend: Double = 0, isTomorrowWeekend: Double = 0,
        meanBedtime7d: Double = 23, meanWake7d: Double = 7, stdBedtime7d: Double = 0.5,
        sleepDebt: Double = 0, lastSleepDuration: Double = 8, processS: Double = 0.4,
        acrophase: Double = 15, cosinorR2: Double = 0.5,
        exerciseToday: Double = 0, caffeineToday: Double = 0,
        melatoninToday: Double = 0, stressToday: Double = 0, alcoholToday: Double = 0,
        driftRate: Double = 0, consistencyScore: Double = 50, chronotypeShift: Double = 0,
        dataCount: Int = 0
    ) {
        self.sinHour = sinHour; self.cosHour = cosHour
        self.isWeekend = isWeekend; self.isTomorrowWeekend = isTomorrowWeekend
        self.meanBedtime7d = meanBedtime7d; self.meanWake7d = meanWake7d; self.stdBedtime7d = stdBedtime7d
        self.sleepDebt = sleepDebt; self.lastSleepDuration = lastSleepDuration; self.processS = processS
        self.acrophase = acrophase; self.cosinorR2 = cosinorR2
        self.exerciseToday = exerciseToday; self.caffeineToday = caffeineToday
        self.melatoninToday = melatoninToday; self.stressToday = stressToday; self.alcoholToday = alcoholToday
        self.driftRate = driftRate; self.consistencyScore = consistencyScore; self.chronotypeShift = chronotypeShift
        self.dataCount = dataCount
    }
}

// MARK: - Prediction Output

/// Result of a sleep prediction for a target night.
public struct PredictionOutput: Codable, Sendable {
    public var predictedBedtimeHour: Double     // clock hour 0-24
    public var predictedWakeHour: Double         // clock hour 0-24
    public var predictedDuration: Double         // hours
    public var confidence: PredictionConfidence
    public var engine: PredictionEngine
    public var generatedAt: Date
    public var targetDate: Date                  // the night this predicts

    public init(
        predictedBedtimeHour: Double, predictedWakeHour: Double, predictedDuration: Double,
        confidence: PredictionConfidence, engine: PredictionEngine = .heuristic,
        generatedAt: Date = Date(), targetDate: Date
    ) {
        self.predictedBedtimeHour = predictedBedtimeHour
        self.predictedWakeHour = predictedWakeHour
        self.predictedDuration = predictedDuration
        self.confidence = confidence
        self.engine = engine
        self.generatedAt = generatedAt
        self.targetDate = targetDate
    }
}

public enum PredictionConfidence: String, Codable, Sendable {
    case low        // < 4 days data or consistency < 30
    case medium     // 4-6 days or consistency 30-60
    case high       // >= 7 days and consistency > 60
}

public enum PredictionEngine: String, Codable, Sendable {
    case heuristic
    case ml
}

// MARK: - Prediction Result (Persistence + Evaluation)

/// A persisted prediction with optional actual data for accuracy tracking.
public struct PredictionResult: Codable, Sendable, Identifiable {
    public var id: UUID
    public var prediction: PredictionOutput
    public var input: PredictionInput
    public var actual: PredictionActual?
    public var errorBedtimeMinutes: Double?
    public var errorWakeMinutes: Double?

    public init(
        id: UUID = UUID(),
        prediction: PredictionOutput,
        input: PredictionInput,
        actual: PredictionActual? = nil,
        errorBedtimeMinutes: Double? = nil,
        errorWakeMinutes: Double? = nil
    ) {
        self.id = id
        self.prediction = prediction
        self.input = input
        self.actual = actual
        self.errorBedtimeMinutes = errorBedtimeMinutes
        self.errorWakeMinutes = errorWakeMinutes
    }

    /// Fill in actual data and compute errors.
    public mutating func evaluate(bedtime: Double, wake: Double, duration: Double) {
        self.actual = PredictionActual(bedtimeHour: bedtime, wakeHour: wake, duration: duration)
        // Circular difference for bedtime (handles midnight wrap)
        let bedDiff = circularDiff(prediction.predictedBedtimeHour, bedtime)
        let wakeDiff = prediction.predictedWakeHour - wake
        self.errorBedtimeMinutes = bedDiff * 60
        self.errorWakeMinutes = wakeDiff * 60
    }

    /// Circular difference on a 24h clock (returns hours, signed).
    private func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        if d > 12 { d -= 24 }
        if d < -12 { d += 24 }
        return d
    }
}

public struct PredictionActual: Codable, Sendable {
    public var bedtimeHour: Double
    public var wakeHour: Double
    public var duration: Double

    public init(bedtimeHour: Double, wakeHour: Double, duration: Double) {
        self.bedtimeHour = bedtimeHour
        self.wakeHour = wakeHour
        self.duration = duration
    }
}
