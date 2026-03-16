import Foundation
import CoreML
import SpiralKit

/// Core ML sleep prediction engine.
///
/// Supports two model formats:
/// 1. **Neural Network** (updatable) — single `features` MultiArray(21) input.
///    Preferred.  Produced by `train_updatable_model.py`.
/// 2. **Gradient Boosting** (legacy) — 21 individual Double inputs.
///    Produced by `train_sleep_model.py`.
///
/// The model outputs bedtime in a CONTINUOUS range (18-30 hours, where
/// 24 = midnight, 25 = 1 AM). This engine converts back to 0-24.
///
/// Load priority:
/// 1. Personalised NN (Documents/models/ — from MLUpdateTask)
/// 2. Bundle updatable NN  (SleepPredictorUpdatable.mlmodel)
/// 3. Bundle GB fallback    (SleepPredictor.mlmodel)
/// 4. HeuristicPredictionEngine (ultimate fallback)
enum MLPredictionEngine {

    // MARK: - Model Management

    /// The currently loaded Core ML model.
    private static var model: MLModel? = loadModelFromDisk()

    /// Whether the loaded model uses MultiArray input (NN) vs individual Doubles (GB).
    private static var isNNModel: Bool = false

    /// Load the best available model from disk.
    private static func loadModelFromDisk() -> MLModel? {
        // 1. Personalised model from MLUpdateTask (.mlmodelc directory)
        let personalisedURL = ModelTrainingService.personalisedModelURL
        if FileManager.default.fileExists(atPath: personalisedURL.path),
           let m = try? MLModel(contentsOf: personalisedURL) {
            isNNModel = true
            return m
        }

        // 2. Bundle updatable NN model
        if let nnURL = Bundle.main.url(forResource: "SleepPredictorUpdatable", withExtension: "mlmodelc") {
            if let m = try? MLModel(contentsOf: nnURL) {
                isNNModel = true
                return m
            }
        }
        if let nnURL = Bundle.main.url(forResource: "SleepPredictorUpdatable", withExtension: "mlmodel") {
            if let compiled = try? MLModel.compileModel(at: nnURL),
               let m = try? MLModel(contentsOf: compiled) {
                isNNModel = true
                return m
            }
        }

        // 3. Bundle GB model (legacy fallback)
        if let gbURL = Bundle.main.url(forResource: "SleepPredictor", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "SleepPredictor", withExtension: "mlmodel") {
            if let m = try? MLModel(contentsOf: gbURL) {
                isNNModel = false
                return m
            }
        }

        return nil
    }

    /// Whether the Core ML model is available and loaded.
    static var isAvailable: Bool { model != nil }

    /// Whether the currently loaded model has been personalised on-device.
    static var isPersonalised: Bool {
        ModelTrainingService.hasPersonalisedModel
    }

    /// Reload model (e.g. after on-device retraining).
    static func reloadModel() {
        model = loadModelFromDisk()
    }

    // MARK: - Prediction

    /// Predict tonight's sleep using the Core ML model.
    ///
    /// If Core ML fails for any reason, falls back to the heuristic engine.
    static func predict(from input: PredictionInput, targetDate: Date = Date()) -> PredictionOutput {
        guard let model else {
            return HeuristicPredictionEngine.predict(from: input, targetDate: targetDate)
        }

        do {
            let prediction: Double
            if isNNModel {
                prediction = try runNNModel(model: model, input: input)
            } else {
                prediction = try runGBModel(model: model, input: input)
            }

            // Convert continuous bedtime (18-30) to clock hour (0-24)
            var bed = prediction.truncatingRemainder(dividingBy: 24)
            if bed < 0 { bed += 24 }

            // Sanity check: reasonable bedtime range 18:00 (6 PM) – 06:00 (6 AM)
            let isReasonable = (bed >= 18 && bed <= 24) || (bed >= 0 && bed <= 6)
            if !isReasonable {
                return HeuristicPredictionEngine.predict(from: input, targetDate: targetDate)
            }

            // Wake prediction: bed + typical duration (clamped 5-11h)
            let duration = max(5.0, min(11.0, input.lastSleepDuration))
            var wake = bed + duration
            if wake >= 24 { wake -= 24 }

            let confidence = computeConfidence(
                dataCount: input.dataCount,
                consistency: input.consistencyScore
            )

            return PredictionOutput(
                predictedBedtimeHour: bed,
                predictedWakeHour: wake,
                predictedDuration: duration,
                confidence: confidence,
                engine: .ml,
                generatedAt: Date(),
                targetDate: targetDate
            )
        } catch {
            // Core ML failed — fall back to heuristic
            return HeuristicPredictionEngine.predict(from: input, targetDate: targetDate)
        }
    }

    // MARK: - Neural Network Model (MultiArray input)

    /// Run the NN model: single `features` MultiArray(21) input.
    private static func runNNModel(model: MLModel, input: PredictionInput) throws -> Double {
        let features = try MLMultiArray(shape: [21], dataType: .double)
        features[0]  = NSNumber(value: input.sinHour)
        features[1]  = NSNumber(value: input.cosHour)
        features[2]  = NSNumber(value: input.isWeekend)
        features[3]  = NSNumber(value: input.isTomorrowWeekend)
        features[4]  = NSNumber(value: input.meanBedtime7d)
        features[5]  = NSNumber(value: input.meanWake7d)
        features[6]  = NSNumber(value: input.stdBedtime7d)
        features[7]  = NSNumber(value: input.sleepDebt)
        features[8]  = NSNumber(value: input.lastSleepDuration)
        features[9]  = NSNumber(value: input.processS)
        features[10] = NSNumber(value: input.acrophase)
        features[11] = NSNumber(value: input.cosinorR2)
        features[12] = NSNumber(value: input.exerciseToday)
        features[13] = NSNumber(value: input.caffeineToday)
        features[14] = NSNumber(value: input.melatoninToday)
        features[15] = NSNumber(value: input.stressToday)
        features[16] = NSNumber(value: input.alcoholToday)
        features[17] = NSNumber(value: input.driftRate)
        features[18] = NSNumber(value: input.consistencyScore)
        features[19] = NSNumber(value: input.chronotypeShift)
        features[20] = NSNumber(value: Double(input.dataCount))

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "features": MLFeatureValue(multiArray: features)
        ])
        let result = try model.prediction(from: provider)

        // NN outputs MultiArray(1) — extract the single value
        if let multiArray = result.featureValue(for: "predictedBedtimeHour")?.multiArrayValue {
            return multiArray[0].doubleValue
        }
        // Or it might be a scalar Double
        if let scalar = result.featureValue(for: "predictedBedtimeHour")?.doubleValue {
            return scalar
        }
        throw MLPredictionError.missingOutput
    }

    // MARK: - Gradient Boosting Model (individual Double inputs)

    /// Run the GB model: 21 individual Double inputs.
    private static func runGBModel(model: MLModel, input: PredictionInput) throws -> Double {
        let features: [String: Any] = [
            "sinHour":             input.sinHour,
            "cosHour":             input.cosHour,
            "isWeekend":           input.isWeekend,
            "isTomorrowWeekend":   input.isTomorrowWeekend,
            "meanBedtime7d":       input.meanBedtime7d,
            "meanWake7d":          input.meanWake7d,
            "stdBedtime7d":        input.stdBedtime7d,
            "sleepDebt":           input.sleepDebt,
            "lastSleepDuration":   input.lastSleepDuration,
            "processS":            input.processS,
            "acrophase":           input.acrophase,
            "cosinorR2":           input.cosinorR2,
            "exerciseToday":       input.exerciseToday,
            "caffeineToday":       input.caffeineToday,
            "melatoninToday":      input.melatoninToday,
            "stressToday":         input.stressToday,
            "alcoholToday":        input.alcoholToday,
            "driftRate":           input.driftRate,
            "consistencyScore":    input.consistencyScore,
            "chronotypeShift":     input.chronotypeShift,
            "dataCount":           Double(input.dataCount),
        ]

        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        let result = try model.prediction(from: provider)

        guard let bedtime = result.featureValue(for: "predictedBedtimeHour")?.doubleValue else {
            throw MLPredictionError.missingOutput
        }

        return bedtime
    }

    // MARK: - Confidence

    private static func computeConfidence(dataCount: Int, consistency: Double) -> PredictionConfidence {
        // Personalised model gets a confidence boost
        let personalised = isPersonalised

        if dataCount >= 7 && consistency > 60 {
            return .high
        }
        if personalised && dataCount >= 5 {
            return .high  // Personalised model is more reliable with less data
        }
        if dataCount >= 4 || consistency > 30 {
            return .medium
        }
        return .low
    }
}

// MARK: - Errors

private enum MLPredictionError: Error {
    case missingOutput
}
