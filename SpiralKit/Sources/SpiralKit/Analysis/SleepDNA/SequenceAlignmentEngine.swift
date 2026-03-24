import Foundation

// MARK: - Supporting Types

/// Result of aligning a partial week against a historical week.
public struct WeekAlignment: Codable, Sendable {
    /// Index of the historical week in the input array.
    public let weekIndex: Int
    /// The start day of the historical week.
    public let startDay: Int
    /// Raw DTW distance score (lower = more similar).
    public let dtwScore: Double
    /// Similarity metric: 1 / (1 + dtwScore). Range [0, 1].
    public let similarity: Double

    public init(weekIndex: Int, startDay: Int, dtwScore: Double, similarity: Double) {
        self.weekIndex = weekIndex
        self.startDay = startDay
        self.dtwScore = dtwScore
        self.similarity = similarity
    }
}

/// Prediction derived from sequence alignment against historical weeks.
public struct SequencePrediction: Codable, Sendable {
    /// Predicted bedtime hour [0, 24).
    public let predictedBedtime: Double
    /// Predicted wake hour [0, 24).
    public let predictedWake: Double
    /// Predicted sleep duration in hours.
    public let predictedDuration: Double
    /// Confidence score [0, 1].
    public let confidence: Double
    /// Indices of historical weeks used in the prediction.
    public let basedOnWeekIndices: [Int]

    public init(
        predictedBedtime: Double,
        predictedWake: Double,
        predictedDuration: Double,
        confidence: Double,
        basedOnWeekIndices: [Int]
    ) {
        self.predictedBedtime = predictedBedtime
        self.predictedWake = predictedWake
        self.predictedDuration = predictedDuration
        self.confidence = confidence
        self.basedOnWeekIndices = basedOnWeekIndices
    }
}

// MARK: - Sequence Alignment Engine

/// Prediction engine that uses partial-week DTW alignment against historical
/// week sequences to predict bedtime and wake time.
///
/// Given the current in-progress week (partial days) and a library of historical
/// full-week sequences, the engine finds the most similar historical patterns
/// and uses the "next day" from those weeks to predict tonight's sleep.
public enum SequenceAlignmentEngine {

    /// Predict tonight's sleep using partial-week alignment against history.
    ///
    /// - Parameters:
    ///   - currentDays: The current in-progress week's nucleotides (>= 2 days).
    ///   - history: Historical complete week sequences (>= 4 weeks).
    ///   - weights: Optional per-feature weight vector for DTW distance.
    ///   - targetDate: The date being predicted for.
    /// - Returns: A tuple of (PredictionOutput, SequencePrediction, [WeekAlignment]),
    ///            or nil if insufficient data.
    public static func predict(
        currentDays: [DayNucleotide],
        history: [WeekSequence],
        weights: [Double]?,
        targetDate: Date
    ) -> (output: PredictionOutput, prediction: SequencePrediction, alignments: [WeekAlignment])? {

        // 1. Guard minimum data requirements
        guard currentDays.count >= 2 else { return nil }
        guard history.count >= 4 else { return nil }

        // 2. DTW-partial each historical week against currentDays
        var alignments: [WeekAlignment] = []
        for (index, week) in history.enumerated() {
            let result = DTWEngine.partialDistance(
                partial: currentDays,
                full: week,
                weights: weights
            )
            let similarity = 1.0 / (1.0 + result.distance)
            alignments.append(WeekAlignment(
                weekIndex: index,
                startDay: week.startDay,
                dtwScore: result.distance,
                similarity: similarity
            ))
        }

        // 3. Rank by DTW score (ascending), take top 5
        alignments.sort { $0.dtwScore < $1.dtwScore }
        let topK = min(5, alignments.count)
        let topAlignments = alignments[..<topK]

        // 4. For each top week, look at the NEXT day after currentDays.count
        let nextDayIndex = currentDays.count // 0-based index within the 7-day week
        var bedtimeSinSum = 0.0
        var bedtimeCosSum = 0.0
        var wakeSinSum = 0.0
        var wakeCosSum = 0.0
        var durationSum = 0.0
        var weightSum = 0.0
        var usedWeekIndices: [Int] = []

        for alignment in topAlignments {
            let week = history[alignment.weekIndex]

            // Skip if the week doesn't have a "next day" at this index
            guard nextDayIndex < week.nucleotides.count else { continue }

            let nextDay = week.nucleotides[nextDayIndex]
            let weight = 1.0 / (1.0 + alignment.dtwScore)

            // Accumulate sin/cos components for circular averaging
            bedtimeSinSum += weight * nextDay[.bedtimeSin]
            bedtimeCosSum += weight * nextDay[.bedtimeCos]
            wakeSinSum += weight * nextDay[.wakeupSin]
            wakeCosSum += weight * nextDay[.wakeupCos]

            // Duration from feature[4] * 12.0
            durationSum += weight * nextDay[.sleepDuration] * 12.0

            weightSum += weight
            usedWeekIndices.append(alignment.weekIndex)
        }

        guard weightSum > 0 else { return nil }

        // 5. Decode bedtime/wake from sin/cos via weighted average
        let avgBedSin = bedtimeSinSum / weightSum
        let avgBedCos = bedtimeCosSum / weightSum
        let avgWakeSin = wakeSinSum / weightSum
        let avgWakeCos = wakeCosSum / weightSum

        var bedHour = atan2(avgBedSin, avgBedCos) / (2.0 * .pi) * 24.0
        if bedHour < 0 { bedHour += 24.0 }

        var wakeHour = atan2(avgWakeSin, avgWakeCos) / (2.0 * .pi) * 24.0
        if wakeHour < 0 { wakeHour += 24.0 }

        let duration = durationSum / weightSum

        // 8. Confidence: best similarity score
        let bestSimilarity = topAlignments.first?.similarity ?? 0.0
        let confidence = min(max(bestSimilarity, 0.0), 1.0)

        // 9. Map confidence to PredictionConfidence
        let predictionConfidence: PredictionConfidence
        if confidence > 0.7 {
            predictionConfidence = .high
        } else if confidence > 0.4 {
            predictionConfidence = .medium
        } else {
            predictionConfidence = .low
        }

        // 10. Build outputs
        let sequencePrediction = SequencePrediction(
            predictedBedtime: bedHour,
            predictedWake: wakeHour,
            predictedDuration: duration,
            confidence: confidence,
            basedOnWeekIndices: usedWeekIndices
        )

        let output = PredictionOutput(
            predictedBedtimeHour: bedHour,
            predictedWakeHour: wakeHour,
            predictedDuration: duration,
            confidence: predictionConfidence,
            engine: .sequenceAlignment,
            generatedAt: Date(),
            targetDate: targetDate
        )

        return (output: output, prediction: sequencePrediction, alignments: Array(topAlignments))
    }
}
