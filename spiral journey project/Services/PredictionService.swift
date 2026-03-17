import Foundation
import SpiralKit

/// Orchestrates sleep prediction: builds features → runs engine → stores result.
///
/// Stateless — call `generatePrediction()` from `SpiralStore.recompute()`.
/// Feature-flagged: does nothing if `store.predictionEnabled` is false.
enum PredictionService {

    // MARK: - Ground Truth Evaluation

    /// Compare past predictions against actual sleep records (ground truth).
    ///
    /// Called from `SpiralStore.recompute()` **before** generating a new prediction.
    /// For each unevaluated prediction in history, look for a SleepRecord whose
    /// date matches the prediction's target night. If found, fill in the actual
    /// data and compute the error.
    @MainActor
    static func evaluatePastPredictions(store: SpiralStore) {
        guard store.predictionEnabled else { return }
        guard !store.records.isEmpty else { return }
        store.evaluateUnevaluatedPredictions()
    }

    // MARK: - Bootstrap Historical Ground Truth

    /// Retroactively generate predictions for past days and evaluate them immediately.
    ///
    /// This bootstraps ground truth from existing sleep records so the ML training
    /// pipeline doesn't have to wait 50+ real-time nights. For each day from day 7
    /// onwards (minimum history needed), we:
    /// 1. Build features using only records up to the day before
    /// 2. Run the prediction engine
    /// 3. Immediately evaluate against the actual SleepRecord
    ///
    /// Called once per lifetime (guarded by a migration flag in `SpiralStore`).
    @MainActor
    static func bootstrapHistoricalPredictions(store: SpiralStore) {
        // Guard: only run once
        guard !store.hasBootstrappedPredictions else { return }
        // Need at least 4 records: 3 for history + 1 to evaluate
        guard store.records.count >= 4 else { return }

        let sorted = store.records.sorted { $0.day < $1.day }
        var bootstrapped: [PredictionResult] = []

        // Start from index 3 so we have at least 3 prior records for features
        for i in 3..<sorted.count {
            let targetRecord = sorted[i]
            // Records available "the evening before" this night
            let priorRecords = Array(sorted[0..<i])

            // Simulate an evening prediction (20:00 on that day)
            let absHour = Double(targetRecord.day) * store.period + 20.0

            // Build features with only prior data
            guard let input = PredictionFeatureBuilder.build(
                records: priorRecords,
                events: store.events,
                consistency: store.analysis.consistency,
                chronotypeResult: store.chronotypeResult,
                goalDuration: store.sleepGoal.targetDuration,
                currentAbsHour: absHour,
                period: store.period
            ) else { continue }

            // Run the current engine
            let prediction: PredictionOutput
            if store.mlPredictionEnabled && MLPredictionEngine.isAvailable {
                prediction = MLPredictionEngine.predict(from: input, targetDate: targetRecord.date)
            } else {
                prediction = HeuristicPredictionEngine.predict(from: input, targetDate: targetRecord.date)
            }

            // Create result and immediately evaluate against actual data
            var result = PredictionResult(prediction: prediction, input: input)
            result.evaluate(
                bedtime: targetRecord.bedtimeHour,
                wake: targetRecord.wakeupHour,
                duration: targetRecord.sleepDuration
            )
            bootstrapped.append(result)
        }

        if !bootstrapped.isEmpty {
            store.appendBootstrappedPredictions(bootstrapped)
        }
        store.hasBootstrappedPredictions = true
    }

    // MARK: - Prediction Generation

    /// Generate a sleep prediction for tonight and store the result.
    ///
    /// - Parameters:
    ///   - store: The app's central store (reads records/events, writes prediction).
    ///   - goalDuration: Target sleep duration in hours (from SleepGoal).
    @MainActor
    static func generatePrediction(store: SpiralStore, goalDuration: Double) {
        guard store.predictionEnabled else { return }
        guard !store.records.isEmpty else { return }

        // Current absolute hour on the timeline
        let calendar = Calendar.current
        let now = Date()
        let daysSinceStart = calendar.dateComponents([.day], from: store.startDate, to: now).day ?? 0
        let secondsIntoDay = calendar.dateComponents([.hour, .minute, .second], from: calendar.startOfDay(for: now), to: now)
        let fractionalHour = Double(secondsIntoDay.hour ?? 0)
            + Double(secondsIntoDay.minute ?? 0) / 60.0
            + Double(secondsIntoDay.second ?? 0) / 3600.0
        let currentAbsHour = Double(daysSinceStart) * store.period + fractionalHour

        // Build feature vector
        guard let input = PredictionFeatureBuilder.build(
            records: store.records,
            events: store.events,
            consistency: store.analysis.consistency,
            chronotypeResult: store.chronotypeResult,
            goalDuration: goalDuration,
            currentAbsHour: currentAbsHour,
            period: store.period
        ) else { return }

        // Run ML engine if available, otherwise heuristic
        let prediction: PredictionOutput
        if store.mlPredictionEnabled && MLPredictionEngine.isAvailable {
            prediction = MLPredictionEngine.predict(from: input, targetDate: now)
        } else {
            prediction = HeuristicPredictionEngine.predict(from: input, targetDate: now)
        }
        // TODO: SequenceAlignmentEngine integration

        // Package result
        let result = PredictionResult(
            prediction: prediction,
            input: input
        )

        // Store
        store.updatePrediction(result)
    }
}
