import Foundation
import CoreML
import os
import SpiralKit

/// Manages on-device model personalisation via MLUpdateTask.
///
/// When the user accumulates ≥ 60 evaluated prediction/actual pairs,
/// the service fine-tunes the last layer of the bundled updatable neural
/// network using `MLUpdateTask`.  The personalised model is saved to
/// Documents/models/ and picked up by `MLPredictionEngine` on next reload.
///
/// A held-out 20 % validation split guards against overfitting: if the
/// post-training MAE is not better than pre-training MAE, the update is
/// rejected and the personalised model is rolled back.
///
/// Stateless — call `retrainIfNeeded(store:)` from `SpiralStore.recompute()`.
enum ModelTrainingService {

    // MARK: - Configuration

    /// Minimum evaluated predictions required before retraining is worthwhile.
    static let minimumSamples = 60

    /// Don't retrain more than once per week.
    static let retrainCooldownDays = 7

    private static let logger = Logger(
        subsystem: "xaron.spiral-journey-project",
        category: "ModelTraining"
    )

    // MARK: - Paths

    private static var modelsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
    }

    /// Where the fine-tuned model is saved (compiled .mlmodelc directory).
    static var personalisedModelURL: URL {
        modelsDir.appendingPathComponent("SleepPredictor_personalised.mlmodelc")
    }

    /// Whether a personalised model exists on disk.
    static var hasPersonalisedModel: Bool {
        FileManager.default.fileExists(atPath: personalisedModelURL.path)
    }

    // MARK: - Eligibility

    /// Number of evaluated predictions (with ground truth) available for training.
    @MainActor
    static func evaluatedCount(store: SpiralStore) -> Int {
        store.predictionHistory.filter { $0.actual != nil }.count
    }

    /// Check whether conditions are met for retraining.
    @MainActor
    static func canRetrain(store: SpiralStore) -> Bool {
        guard store.mlPredictionEnabled else { return false }
        guard evaluatedCount(store: store) >= minimumSamples else { return false }

        // Cooldown: at most once per week
        if let lastTrained = store.lastModelTrainedDate {
            let days = Calendar.current.dateComponents(
                [.day], from: lastTrained, to: Date()
            ).day ?? 0
            guard days >= retrainCooldownDays else { return false }
        }

        return true
    }

    // MARK: - Retrain

    /// Fine-tune the updatable NN model with user data, if eligible.
    ///
    /// This is safe to call from `recompute()` — it returns immediately
    /// if the conditions aren't met.  The actual training runs on a
    /// background thread via `MLUpdateTask`.
    @MainActor
    static func retrainIfNeeded(store: SpiralStore) {
        guard canRetrain(store: store) else { return }

        // Mark as training so we don't trigger again during this session
        store.lastModelTrainedDate = Date()

        // Collect training samples from prediction history
        let samples: [(PredictionInput, Double)] = store.predictionHistory.compactMap { result in
            guard let actual = result.actual else { return nil }
            // Convert bedtime to continuous 18-30 (matching model's target space)
            var bed = actual.bedtimeHour
            if bed < 12 { bed += 24 }  // 0-6 AM → 24-30
            return (result.input, bed)
        }

        guard samples.count >= minimumSamples else { return }

        Task.detached(priority: .utility) {
            do {
                let metrics = try await performTraining(samples: samples)
                await MainActor.run {
                    if metrics.accepted {
                        // Reload the prediction engine to use the new model
                        MLPredictionEngine.reloadModel()
                        // Setting this triggers save() via didSet
                        store.modelTrainingSampleCount = metrics.trainCount + metrics.validationCount
                        logger.info(
                            "Training accepted — preMae: \(metrics.preMae, format: .fixed(precision: 3)), postMae: \(metrics.postMae, format: .fixed(precision: 3)), train: \(metrics.trainCount), val: \(metrics.validationCount)"
                        )
                    } else {
                        logger.info(
                            "Training rejected (regression) — preMae: \(metrics.preMae, format: .fixed(precision: 3)), postMae: \(metrics.postMae, format: .fixed(precision: 3))"
                        )
                    }
                }
            } catch {
                // Training failed silently — the base model continues to work.
                // Reset the date so we'll try again later.
                await MainActor.run {
                    store.lastModelTrainedDate = nil
                }
                logger.error("Training failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Training Implementation

    /// Run MLUpdateTask to fine-tune the updatable model with validation split.
    ///
    /// Shuffles all samples, holds out 20 % for validation, trains on 80 %.
    /// If the post-training MAE on validation is not better than pre-training
    /// MAE, the personalised model is rolled back and the update is rejected.
    ///
    /// Runs on a background thread.  Throws if the model isn't updatable
    /// or training data can't be built.
    private static func performTraining(
        samples: [(PredictionInput, Double)]
    ) async throws -> TrainingMetrics {
        // 0. Shuffle and split 80/20
        var shuffled = samples
        shuffled.shuffle()
        let splitIndex = max(1, Int(Double(shuffled.count) * 0.8))
        let trainSamples = Array(shuffled[..<splitIndex])
        let valSamples = Array(shuffled[splitIndex...])

        // 1. Locate the updatable model in the bundle
        guard let bundleURL = Bundle.main.url(
            forResource: "SleepPredictorUpdatable", withExtension: "mlmodelc"
        ) ?? Bundle.main.url(
            forResource: "SleepPredictorUpdatable", withExtension: "mlmodel"
        ) else {
            throw TrainingError.updatableModelNotFound
        }

        // 2. Compile if needed (mlmodel → mlmodelc)
        let compiledURL: URL
        if bundleURL.pathExtension == "mlmodelc" {
            compiledURL = bundleURL
        } else {
            compiledURL = try await MLModel.compileModel(at: bundleURL)
        }

        // 3. Compute pre-training MAE on validation set with current model
        let preMae = computeValidationMAE(samples: valSamples)

        // 4. Build training batch (train split only)
        let batchProvider = try buildTrainingBatch(samples: trainSamples)

        // 5. Ensure output directory exists
        try FileManager.default.createDirectory(
            at: modelsDir, withIntermediateDirectories: true
        )

        let outputURL = personalisedModelURL

        // 6. Run MLUpdateTask
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                let updateTask = try MLUpdateTask(
                    forModelAt: compiledURL,
                    trainingData: batchProvider,
                    configuration: nil,
                    completionHandler: { context in
                        do {
                            // Remove old personalised model if it exists
                            try? FileManager.default.removeItem(at: outputURL)
                            try context.model.write(to: outputURL)
                            cont.resume()
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                )
                updateTask.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }

        // 7. Reload model and compute post-training MAE on validation set
        MLPredictionEngine.reloadModel()
        let postMae = computeValidationMAE(samples: valSamples)

        // 8. Regression guard: reject if post-training is not better
        let accepted = postMae < preMae

        if !accepted {
            // Roll back: delete the personalised model and reload base model
            try? FileManager.default.removeItem(at: outputURL)
            MLPredictionEngine.reloadModel()
            logger.warning(
                "Regression guard triggered — rolling back personalised model (pre: \(preMae, format: .fixed(precision: 3)), post: \(postMae, format: .fixed(precision: 3)))"
            )
        }

        return TrainingMetrics(
            date: Date(),
            preMae: preMae,
            postMae: postMae,
            trainCount: trainSamples.count,
            validationCount: valSamples.count,
            accepted: accepted
        )
    }

    // MARK: - Validation

    /// Compute mean absolute error on a set of samples using the current model.
    ///
    /// Uses `MLPredictionEngine.predict(from:)` and compares the predicted
    /// bedtime hour against the target (both in continuous 18-30 space).
    private static func computeValidationMAE(
        samples: [(PredictionInput, Double)]
    ) -> Double {
        guard !samples.isEmpty else { return .infinity }

        var totalError = 0.0
        for (input, target) in samples {
            let output = MLPredictionEngine.predict(from: input)
            // Convert predicted bedtime to continuous 18-30 space for comparison
            var predicted = output.predictedBedtimeHour
            if predicted < 12 { predicted += 24 }  // 0-6 AM → 24-30
            totalError += abs(predicted - target)
        }
        return totalError / Double(samples.count)
    }

    // MARK: - Training Data Builder

    /// Convert evaluated prediction samples into an MLBatchProvider.
    ///
    /// Each training sample has:
    /// - `features`: MLMultiArray of shape [21] (PredictionInput fields)
    /// - `predictedBedtimeHour_true`: MLMultiArray of shape [1] (actual bedtime)
    private static func buildTrainingBatch(
        samples: [(PredictionInput, Double)]
    ) throws -> MLArrayBatchProvider {
        var providers: [MLFeatureProvider] = []

        for (input, target) in samples {
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

            let targetArray = try MLMultiArray(shape: [1], dataType: .double)
            targetArray[0] = NSNumber(value: target)

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "features": MLFeatureValue(multiArray: features),
                "predictedBedtimeHour_true": MLFeatureValue(multiArray: targetArray),
            ])
            providers.append(provider)
        }

        return MLArrayBatchProvider(array: providers)
    }
}

// MARK: - Errors

private enum TrainingError: LocalizedError {
    case updatableModelNotFound
    case compilationFailed
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .updatableModelNotFound:
            return "Updatable model not found in bundle"
        case .compilationFailed:
            return "Failed to compile model"
        case .insufficientData:
            return "Not enough training data"
        }
    }
}
