import Foundation
import SwiftData
import SpiralKit

// MARK: - SDPredictionResult

/// SwiftData model mirroring SpiralKit.PredictionResult with the nested
/// PredictionOutput flattened into top-level properties.
@Model
final class SDPredictionResult {

    // MARK: Persisted Properties

    var predictionID: UUID

    // Flattened PredictionOutput
    var predictedBedtimeHour: Double
    var predictedWakeHour: Double
    var predictedDuration: Double
    /// Stored as PredictionConfidence.rawValue ("low" | "medium" | "high").
    var confidence: String
    /// Stored as PredictionEngine.rawValue ("heuristic" | "ml").
    var engine: String
    var generatedAt: Date
    var targetDate: Date

    // PredictionInput stored as JSON blob (too many fields to flatten individually)
    @Attribute(.externalStorage) var inputJSON: Data?

    // PredictionActual (optional)
    var actualBedtimeHour: Double?
    var actualWakeHour: Double?
    var actualDuration: Double?

    // Error metrics
    var errorBedtimeMinutes: Double?
    var errorWakeMinutes: Double?

    // MARK: Init

    init(
        predictionID: UUID = UUID(),
        predictedBedtimeHour: Double,
        predictedWakeHour: Double,
        predictedDuration: Double,
        confidence: String,
        engine: String,
        generatedAt: Date,
        targetDate: Date,
        inputJSON: Data?,
        actualBedtimeHour: Double? = nil,
        actualWakeHour: Double? = nil,
        actualDuration: Double? = nil,
        errorBedtimeMinutes: Double? = nil,
        errorWakeMinutes: Double? = nil
    ) {
        self.predictionID = predictionID
        self.predictedBedtimeHour = predictedBedtimeHour
        self.predictedWakeHour = predictedWakeHour
        self.predictedDuration = predictedDuration
        self.confidence = confidence
        self.engine = engine
        self.generatedAt = generatedAt
        self.targetDate = targetDate
        self.inputJSON = inputJSON
        self.actualBedtimeHour = actualBedtimeHour
        self.actualWakeHour = actualWakeHour
        self.actualDuration = actualDuration
        self.errorBedtimeMinutes = errorBedtimeMinutes
        self.errorWakeMinutes = errorWakeMinutes
    }

    // MARK: Converters

    /// Create an SDPredictionResult from a SpiralKit PredictionResult.
    convenience init(from result: PredictionResult) {
        let encoder = JSONEncoder()
        let inputData = (try? encoder.encode(result.input)) ?? Data()

        self.init(
            predictionID: result.id,
            predictedBedtimeHour: result.prediction.predictedBedtimeHour,
            predictedWakeHour: result.prediction.predictedWakeHour,
            predictedDuration: result.prediction.predictedDuration,
            confidence: result.prediction.confidence.rawValue,
            engine: result.prediction.engine.rawValue,
            generatedAt: result.prediction.generatedAt,
            targetDate: result.prediction.targetDate,
            inputJSON: inputData,
            actualBedtimeHour: result.actual?.bedtimeHour,
            actualWakeHour: result.actual?.wakeHour,
            actualDuration: result.actual?.duration,
            errorBedtimeMinutes: result.errorBedtimeMinutes,
            errorWakeMinutes: result.errorWakeMinutes
        )
    }

    /// Convert back to a SpiralKit PredictionResult.
    func toPredictionResult() -> PredictionResult? {
        let decoder = JSONDecoder()
        guard let data = inputJSON,
              let input = try? decoder.decode(PredictionInput.self, from: data) else {
            return nil
        }

        let output = PredictionOutput(
            predictedBedtimeHour: predictedBedtimeHour,
            predictedWakeHour: predictedWakeHour,
            predictedDuration: predictedDuration,
            confidence: PredictionConfidence(rawValue: confidence) ?? .low,
            engine: PredictionEngine(rawValue: engine) ?? .heuristic,
            generatedAt: generatedAt,
            targetDate: targetDate
        )

        var actual: PredictionActual?
        if let bed = actualBedtimeHour, let wake = actualWakeHour, let dur = actualDuration {
            actual = PredictionActual(bedtimeHour: bed, wakeHour: wake, duration: dur)
        }

        return PredictionResult(
            id: predictionID,
            prediction: output,
            input: input,
            actual: actual,
            errorBedtimeMinutes: errorBedtimeMinutes,
            errorWakeMinutes: errorWakeMinutes
        )
    }
}
