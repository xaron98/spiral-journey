# ML & AI Coach Improvements — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve ML prediction accuracy, migrate storage to SwiftData, add Foundation Models as coach backend with Phi-3.5 fallback, and harden robustness — making the app production-grade.

**Architecture:** Four sequential phases. Phase 1 makes surgical ML fixes (validation, better features, circular math). Phase 2 migrates persistence from JSON/UserDefaults to SwiftData with local-only config (CKSyncEngine preserved). Phase 3 abstracts the coach behind a protocol with Foundation Models (iOS 26+) and Phi-3.5 fallback. Phase 4 improves training data quality, adds metrics tracking, and data retention.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, CoreML, Foundation Models (iOS 26+), LLM package (Phi-3.5 GGUF), Python (training scripts)

**Spec:** `docs/superpowers/specs/2026-03-16-ml-ai-improvements-design.md`

---

## File Structure

### New Files
- `SpiralKit/Sources/SpiralKit/Models/TrainingMetrics.swift` — training validation metrics struct
- `spiral journey project/Models/SDSleepEpisode.swift` — SwiftData model for sleep episodes
- `spiral journey project/Models/SDCircadianEvent.swift` — SwiftData model for circadian events
- `spiral journey project/Models/SDPredictionResult.swift` — SwiftData model for prediction results
- `spiral journey project/Models/SDCoachMessage.swift` — SwiftData model for chat messages
- `spiral journey project/Models/SDUserGoal.swift` — SwiftData model for sleep goal
- `spiral journey project/Models/SDPredictionMetrics.swift` — SwiftData model for metrics
- `spiral journey project/Models/SDTrainingMetrics.swift` — SwiftData model for training metrics
- `spiral journey project/Services/DataMigrationService.swift` — JSON→SwiftData migration
- `spiral journey project/Services/WatchSyncBridge.swift` — observer-based Watch sync
- `spiral journey project/Services/Coach/CoachLLMProvider.swift` — provider protocol
- `spiral journey project/Services/Coach/PhiLLMProvider.swift` — Phi-3.5 adapter
- `spiral journey project/Services/Coach/FoundationModelsProvider.swift` — iOS 26+ adapter
- `spiral journey project/Services/Coach/CoachProviderFactory.swift` — runtime selection
- `spiral journey project/Services/PredictionMetricsTracker.swift` — rolling metrics
- `spiral journey project/Services/DataRetentionService.swift` — retention policies

### Modified Files
- `SpiralKit/Sources/SpiralKit/Models/PredictionModels.swift` — circular diff for wake
- `SpiralKit/Sources/SpiralKit/Analysis/PredictionFeatureBuilder.swift` — continuous Process S
- `spiral journey project/Services/ModelTrainingService.swift` — validation split
- `spiral journey project/Services/MLPredictionEngine.swift` — expose reloadModel
- `spiral journey project/Services/SpiralStore.swift` — SwiftData integration, remove 90-cap
- `spiral journey project/Services/LLMContextBuilder.swift` — prompt tiers
- `spiral journey project/Views/Coach/CoachChatView.swift` — provider protocol
- `spiral journey project/spiral_journey_projectApp.swift` — ModelContainer, migration, bridge
- `Scripts/train_sleep_model.py` — chronotype subpopulations
- `Scripts/train_updatable_model.py` — chronotype subpopulations

**Note:** All new `.swift` files must be added to the Xcode project target (not just created on disk). Use Xcode or update `.pbxproj` manually.

---

## Chunk 1: Phase 1 — ML Pipeline Improvements

### Task 1: Circular Difference for Wake Time

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Models/PredictionModels.swift`
- Test: `SpiralKit/Tests/SpiralKitTests/CircularDiffTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SpiralKit/Tests/SpiralKitTests/CircularDiffTests.swift
import XCTest
@testable import SpiralKit

final class CircularDiffTests: XCTestCase {

    func testNoWrap() {
        // 23.5 vs 23.0 = +0.5h
        XCTAssertEqual(circularTimeDiff(23.5, 23.0), 0.5, accuracy: 0.01)
    }

    func testWrapForwardMidnight() {
        // 23.5 vs 0.25 → +0.75h (not -23.25)
        XCTAssertEqual(circularTimeDiff(0.25, 23.5), 0.75, accuracy: 0.01)
    }

    func testWrapBackwardMidnight() {
        // 1.0 vs 23.0 → -2.0h (not +22h)
        XCTAssertEqual(circularTimeDiff(1.0, 23.0), -2.0, accuracy: 0.01)
    }

    func testIdentical() {
        XCTAssertEqual(circularTimeDiff(6.0, 6.0), 0.0, accuracy: 0.01)
    }

    func testEvaluateUsesCircularForWake() {
        let output = PredictionOutput(
            predictedBedtimeHour: 23.0,
            predictedWakeHour: 23.5,
            predictedDuration: 7.0,
            confidence: .high,
            engine: .heuristic,
            targetDate: Date()
        )
        let input = PredictionInput.empty  // need a minimal PredictionInput
        var result = PredictionResult(prediction: output, input: input)
        result.evaluate(bedtime: 23.5, wake: 0.25, duration: 7.0)
        // Wake diff should be ~0.75h = 45 min, not ~23h
        XCTAssertNotNil(result.errorWakeMinutes)
        XCTAssertLessThan(abs(result.errorWakeMinutes!), 60.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SpiralKit && swift test --filter CircularDiffTests 2>&1 | tail -20`
Expected: FAIL — `circularTimeDiff` not found

- [ ] **Step 3: Extract shared circular diff and fix wake evaluation**

In `PredictionModels.swift`, add a public top-level function (the existing one is private inside evaluate):

```swift
/// Signed circular difference in hours, handling 24h wrap.
/// Returns a - b adjusted to [-12, +12] range.
public func circularTimeDiff(_ a: Double, _ b: Double) -> Double {
    var d = a - b
    if d > 12 { d -= 24 }
    if d < -12 { d += 24 }
    return d
}
```

In `PredictionResult.evaluate(bedtime:wake:duration:)`, change the wake line:

```swift
// BEFORE:
errorWakeMinutes = (prediction.predictedWakeHour - wake) * 60

// AFTER:
errorWakeMinutes = circularTimeDiff(prediction.predictedWakeHour, wake) * 60
```

Also update the bed line to use the shared function:
```swift
// BEFORE (uses private circularDiff):
errorBedtimeMinutes = circularDiff(prediction.predictedBedtimeHour, bedtime) * 60

// AFTER:
errorBedtimeMinutes = circularTimeDiff(prediction.predictedBedtimeHour, bedtime) * 60
```

Remove the old private `circularDiff` method.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SpiralKit && swift test --filter CircularDiffTests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Build iOS project**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Models/PredictionModels.swift \
      SpiralKit/Tests/SpiralKitTests/CircularDiffTests.swift
git commit -m "fix: use circular difference for wake time evaluation

Extract circularTimeDiff() as public helper. Apply to both bed and wake
in PredictionResult.evaluate(). Fixes midnight-crossing wake errors."
```

---

### Task 2: Validation Split in On-Device Retraining

**Files:**
- Modify: `spiral journey project/Services/ModelTrainingService.swift`
- Modify: `spiral journey project/Services/MLPredictionEngine.swift`
- Create: `SpiralKit/Sources/SpiralKit/Models/TrainingMetrics.swift`

- [ ] **Step 1: Create TrainingMetrics model**

```swift
// SpiralKit/Sources/SpiralKit/Models/TrainingMetrics.swift
import Foundation

public struct TrainingMetrics: Codable, Sendable {
    public let date: Date
    public let preMae: Double
    public let postMae: Double
    public let trainCount: Int
    public let validationCount: Int
    public let accepted: Bool

    public init(date: Date, preMae: Double, postMae: Double,
                trainCount: Int, validationCount: Int, accepted: Bool) {
        self.date = date
        self.preMae = preMae
        self.postMae = postMae
        self.trainCount = trainCount
        self.validationCount = validationCount
        self.accepted = accepted
    }
}
```

- [ ] **Step 2: Update minimumSamples from 50 to 60**

In `ModelTrainingService.swift`, change:
```swift
// BEFORE (line 18):
static let minimumSamples = 50

// AFTER:
static let minimumSamples = 60
```

- [ ] **Step 3: Ensure MLPredictionEngine.reloadModel() is internal (not private)**

In `MLPredictionEngine.swift`, verify `reloadModel()` is accessible:
```swift
// Should be (line ~77):
static func reloadModel() {
    model = loadModelFromDisk()
}
```
If it's `private`, remove the `private` modifier.

- [ ] **Step 4: Add validation split to performTraining**

In `ModelTrainingService.swift`, modify the `performTraining` method. Keep it `private static func ... async throws`. Add validation logic:

```swift
private static func performTraining(
    samples: [(PredictionInput, Double)]
) async throws -> TrainingMetrics {
    // 1. Shuffle and split 80/20
    var shuffled = samples.shuffled()
    let splitIndex = Int(Double(shuffled.count) * 0.8)
    let trainSamples = Array(shuffled[0..<splitIndex])
    let validationSamples = Array(shuffled[splitIndex...])

    // 2. Pre-training MAE on validation set
    let preMae = computeMAE(on: validationSamples)

    // 3. Build training batch from trainSamples only
    let batch = try buildTrainingBatch(samples: trainSamples)
    guard batch.count > 0 else {
        throw TrainingError.emptyBatch
    }

    // 4. Run MLUpdateTask with train-only batch
    // ... existing MLUpdateTask code, using `batch` ...

    // 5. Reload and compute post-training MAE
    MLPredictionEngine.reloadModel()
    let postMae = computeMAE(on: validationSamples)

    // 6. Regression guard
    let accepted = postMae < preMae
    if !accepted {
        try? FileManager.default.removeItem(at: personalisedModelURL)
        MLPredictionEngine.reloadModel()
        print("[ModelTraining] Regression: pre=\(String(format:"%.3f",preMae)) post=\(String(format:"%.3f",postMae)). Reverted.")
    } else {
        print("[ModelTraining] Improved: pre=\(String(format:"%.3f",preMae)) → post=\(String(format:"%.3f",postMae)). Accepted.")
    }

    return TrainingMetrics(
        date: Date(), preMae: preMae, postMae: postMae,
        trainCount: trainSamples.count,
        validationCount: validationSamples.count,
        accepted: accepted
    )
}

/// Compute MAE on validation set using current loaded model
private static func computeMAE(on samples: [(PredictionInput, Double)]) -> Double {
    var totalError = 0.0
    var count = 0
    for sample in samples {
        let output = MLPredictionEngine.predict(from: sample.0, targetDate: Date())
        let predicted = output.predictedBedtimeHour
        let continuous = predicted < 18 ? predicted + 24 : predicted
        totalError += abs(continuous - sample.1)
        count += 1
    }
    return count > 0 ? totalError / Double(count) : .greatestFiniteMagnitude
}

enum TrainingError: Error {
    case emptyBatch
}
```

- [ ] **Step 5: Update retrainIfNeeded to handle TrainingMetrics return**

The caller `retrainIfNeeded` currently calls `try await performTraining(samples:)` with no return. Update it to capture the metrics:

```swift
let metrics = try await performTraining(samples: samples)
// Optionally store metrics in SpiralStore or log
print("[ModelTraining] Metrics: \(metrics)")
```

- [ ] **Step 6: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add spiral\ journey\ project/Services/ModelTrainingService.swift \
      spiral\ journey\ project/Services/MLPredictionEngine.swift \
      SpiralKit/Sources/SpiralKit/Models/TrainingMetrics.swift
git commit -m "feat: add validation split and regression guard to ML retraining

80/20 train/validation split. Pre/post MAE comparison on validation
set. Stale personalised model deleted from disk on regression.
Minimum samples raised to 60."
```

---

### Task 3: Continuous Process S in Feature Builder

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Analysis/PredictionFeatureBuilder.swift`
- Test: `SpiralKit/Tests/SpiralKitTests/ContinuousProcessSTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// SpiralKit/Tests/SpiralKitTests/ContinuousProcessSTests.swift
import XCTest
@testable import SpiralKit

final class ContinuousProcessSTests: XCTestCase {

    func testContinuousSReflectsDebt() {
        // Build 7 days: 4 normal (8h) + 3 short (5h)
        // computeContinuous propagates debt → S should be elevated
        let records = makeRecords(normalNights: 4, shortNights: 3)
        let continuousPoints = TwoProcessModel.computeContinuous(records)
        guard let lastPoint = continuousPoints.last else {
            XCTFail("No points returned")
            return
        }
        // After short sleep, S should be elevated (>0.5 midday)
        XCTAssertGreaterThan(lastPoint.s, 0.4,
            "Continuous S should be elevated after sleep debt")
    }

    func testContinuousSStableWithNormalSleep() {
        let records = makeRecords(normalNights: 7, shortNights: 0)
        let points = TwoProcessModel.computeContinuous(records)
        guard let lastPoint = points.last else {
            XCTFail("No points returned")
            return
        }
        // Should be in normal range
        XCTAssertGreaterThan(lastPoint.s, 0.1)
        XCTAssertLessThan(lastPoint.s, 0.9)
    }

    func testExtractContinuousSFromBuilder() {
        let records = makeRecords(normalNights: 7, shortNights: 0)
        let s = PredictionFeatureBuilder.continuousProcessS(
            from: records, currentHour: 14
        )
        XCTAssertGreaterThan(s, 0.0)
        XCTAssertLessThan(s, 1.0)
    }

    func testEmptyRecordsFallback() {
        let s = PredictionFeatureBuilder.continuousProcessS(
            from: [], currentHour: 14
        )
        XCTAssertGreaterThan(s, 0.0)
        XCTAssertLessThan(s, 1.0)
    }

    // MARK: - Helpers

    private func makeRecords(normalNights: Int, shortNights: Int) -> [SleepRecord] {
        var records: [SleepRecord] = []
        let total = normalNights + shortNights
        let cal = Calendar.current
        let baseDate = cal.startOfDay(for: Date())

        for i in 0..<total {
            let dayOffset = -(total - 1 - i)
            let date = cal.date(byAdding: .day, value: dayOffset, to: baseDate)!
            let isShort = i >= normalNights
            let duration = isShort ? 5.0 : 8.0
            let bedHour = 23.0
            let wakeHour = bedHour + duration - 24.0  // normalize past midnight

            records.append(SleepRecord(
                day: i,
                date: date,
                isWeekend: cal.isDateInWeekend(date),
                bedtimeHour: bedHour,
                wakeupHour: wakeHour > 0 ? wakeHour : wakeHour + 24,
                sleepDuration: duration,
                phases: [],
                hourlyActivity: [],
                cosinor: CosinorResult.empty
            ))
        }
        return records
    }
}
```

**Note:** `CosinorResult.empty` may need to be a static default. If it doesn't exist, create a minimal one or use the default init. Adjust as needed for existing API.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SpiralKit && swift test --filter ContinuousProcessSTests 2>&1 | tail -20`
Expected: FAIL — `continuousProcessS` not found

- [ ] **Step 3: Add continuousProcessS to PredictionFeatureBuilder**

In `PredictionFeatureBuilder.swift`:

```swift
/// Compute Process S using continuous model with sleep-debt memory.
/// Falls back to stateless processS() if records insufficient.
public static func continuousProcessS(
    from records: [SleepRecord],
    currentHour: Int
) -> Double {
    guard records.count >= 2 else {
        // Fallback: snapshot without debt memory
        let hoursSinceWake = max(Double(currentHour) - 8.0, 1.0)
        return TwoProcessModel.processS(
            hoursSinceTransition: hoursSinceWake, isAwake: true, s0: 0.2
        )
    }

    let points = TwoProcessModel.computeContinuous(records)
    guard !points.isEmpty else {
        return TwoProcessModel.processS(
            hoursSinceTransition: 6.0, isAwake: true, s0: 0.2
        )
    }

    // Find the point closest to currentHour on the last day
    let lastDay = points.last!.day
    if let match = points.last(where: { $0.day == lastDay && $0.hour <= currentHour }) {
        return match.s
    }
    return points.last!.s
}
```

- [ ] **Step 4: Replace processS() call in build()**

In `PredictionFeatureBuilder.swift`, at the line where `processS` is computed (line ~62):

```swift
// BEFORE:
let processS = TwoProcessModel.processS(
    hoursSinceTransition: hoursSinceWake, isAwake: true, s0: 0.2
)

// AFTER:
let currentHour = Calendar.current.component(.hour, from: Date())
let processS = Self.continuousProcessS(from: records, currentHour: currentHour)
```

- [ ] **Step 5: Run tests**

Run: `cd SpiralKit && swift test --filter ContinuousProcessSTests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 6: Build iOS project**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Analysis/PredictionFeatureBuilder.swift \
      SpiralKit/Tests/SpiralKitTests/ContinuousProcessSTests.swift
git commit -m "feat: use continuous Process S with sleep-debt memory

Replace stateless processS() with computeContinuous() that propagates
sleep pressure across 7 days. Falls back to snapshot if <2 records."
```

---

## Chunk 2: Phase 2 — SwiftData Migration

### Task 4: SwiftData Models

**Files:**
- Create: `spiral journey project/Models/SDSleepEpisode.swift`
- Create: `spiral journey project/Models/SDCircadianEvent.swift`
- Create: `spiral journey project/Models/SDPredictionResult.swift`
- Create: `spiral journey project/Models/SDCoachMessage.swift`
- Create: `spiral journey project/Models/SDUserGoal.swift`
- Create: `spiral journey project/Models/SDPredictionMetrics.swift`
- Create: `spiral journey project/Models/SDTrainingMetrics.swift`

- [ ] **Step 1: Create SDSleepEpisode**

```swift
// spiral journey project/Models/SDSleepEpisode.swift
import Foundation
import SwiftData
import SpiralKit

@Model
final class SDSleepEpisode {
    var id: UUID
    var start: Double
    var end: Double
    var source: String          // DataSource.rawValue
    var healthKitSampleID: String?
    var phase: String?          // SleepPhase.rawValue
    var modifiedAt: Date        // change tracking for WatchSyncBridge & CloudSyncManager

    init(id: UUID = UUID(), start: Double, end: Double, source: String,
         healthKitSampleID: String? = nil, phase: String? = nil,
         modifiedAt: Date = Date()) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        self.healthKitSampleID = healthKitSampleID
        self.phase = phase
        self.modifiedAt = modifiedAt
    }

    convenience init(from episode: SleepEpisode) {
        self.init(
            id: episode.id, start: episode.start, end: episode.end,
            source: episode.source.rawValue,
            healthKitSampleID: episode.healthKitSampleID,
            phase: episode.phase?.rawValue
        )
    }

    func toSleepEpisode() -> SleepEpisode {
        SleepEpisode(
            id: id, start: start, end: end,
            source: DataSource(rawValue: source) ?? .manual,
            healthKitSampleID: healthKitSampleID,
            phase: phase.flatMap { SleepPhase(rawValue: $0) }
        )
    }
}
```

- [ ] **Step 2: Create SDCircadianEvent**

```swift
// spiral journey project/Models/SDCircadianEvent.swift
import Foundation
import SwiftData
import SpiralKit

@Model
final class SDCircadianEvent {
    var id: UUID
    var type: String            // EventType.rawValue
    var absoluteHour: Double
    var timestamp: Date
    var note: String?

    init(id: UUID = UUID(), type: String, absoluteHour: Double,
         timestamp: Date = Date(), note: String? = nil) {
        self.id = id
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
    }

    convenience init(from event: CircadianEvent) {
        self.init(
            id: event.id, type: event.type.rawValue,
            absoluteHour: event.absoluteHour,
            timestamp: event.timestamp, note: event.note
        )
    }

    func toCircadianEvent() -> CircadianEvent {
        CircadianEvent(
            id: id,
            type: EventType(rawValue: type) ?? .caffeine,
            absoluteHour: absoluteHour,
            timestamp: timestamp,
            note: note
        )
    }
}
```

- [ ] **Step 3: Create SDPredictionResult with converters**

```swift
// spiral journey project/Models/SDPredictionResult.swift
import Foundation
import SwiftData
import SpiralKit

@Model
final class SDPredictionResult {
    var id: UUID
    var targetDate: Date
    var predictedBedtimeHour: Double
    var predictedWakeHour: Double
    var predictedDuration: Double
    var confidence: String      // PredictionConfidence.rawValue
    var engine: String          // PredictionEngine.rawValue
    var generatedAt: Date
    // Actual values (set after evaluation)
    var actualBedtime: Double?
    var actualWake: Double?
    var actualDuration: Double?
    var bedError: Double?       // errorBedtimeMinutes
    var wakeError: Double?      // errorWakeMinutes

    init(id: UUID = UUID(), targetDate: Date,
         predictedBedtimeHour: Double, predictedWakeHour: Double,
         predictedDuration: Double, confidence: String, engine: String,
         generatedAt: Date = Date()) {
        self.id = id
        self.targetDate = targetDate
        self.predictedBedtimeHour = predictedBedtimeHour
        self.predictedWakeHour = predictedWakeHour
        self.predictedDuration = predictedDuration
        self.confidence = confidence
        self.engine = engine
        self.generatedAt = generatedAt
    }

    convenience init(from result: PredictionResult) {
        self.init(
            id: result.id,
            targetDate: result.prediction.targetDate,
            predictedBedtimeHour: result.prediction.predictedBedtimeHour,
            predictedWakeHour: result.prediction.predictedWakeHour,
            predictedDuration: result.prediction.predictedDuration,
            confidence: result.prediction.confidence.rawValue,
            engine: result.prediction.engine.rawValue,
            generatedAt: result.prediction.generatedAt
        )
        if let actual = result.actual {
            self.actualBedtime = actual.bedtime
            self.actualWake = actual.wake
            self.actualDuration = actual.duration
        }
        self.bedError = result.errorBedtimeMinutes
        self.wakeError = result.errorWakeMinutes
    }
}
```

- [ ] **Step 4: Create SDCoachMessage**

```swift
// spiral journey project/Models/SDCoachMessage.swift
import Foundation
import SwiftData

@Model
final class SDCoachMessage {
    var id: UUID
    var timestamp: Date
    var role: String            // "user" | "assistant" | "system"
    var content: String

    init(id: UUID = UUID(), timestamp: Date = Date(), role: String, content: String) {
        self.id = id
        self.timestamp = timestamp
        self.role = role
        self.content = content
    }
}
```

- [ ] **Step 5: Create SDUserGoal**

```swift
// spiral journey project/Models/SDUserGoal.swift
import Foundation
import SwiftData
import SpiralKit

@Model
final class SDUserGoal {
    var id: UUID
    var mode: String            // CoachMode.rawValue
    var targetBedHour: Double
    var targetWakeHour: Double
    var targetDuration: Double
    var toleranceMinutes: Double
    var allowsSplitSleep: Bool
    var rephaseStepMinutes: Double
    var updatedAt: Date

    init(id: UUID = UUID(), mode: String, targetBedHour: Double,
         targetWakeHour: Double, targetDuration: Double,
         toleranceMinutes: Double = 90, allowsSplitSleep: Bool = false,
         rephaseStepMinutes: Double = 0, updatedAt: Date = Date()) {
        self.id = id
        self.mode = mode
        self.targetBedHour = targetBedHour
        self.targetWakeHour = targetWakeHour
        self.targetDuration = targetDuration
        self.toleranceMinutes = toleranceMinutes
        self.allowsSplitSleep = allowsSplitSleep
        self.rephaseStepMinutes = rephaseStepMinutes
        self.updatedAt = updatedAt
    }

    convenience init(from goal: SleepGoal) {
        self.init(
            mode: goal.mode.rawValue,
            targetBedHour: goal.targetBedHour,
            targetWakeHour: goal.targetWakeHour,
            targetDuration: goal.targetDuration,
            toleranceMinutes: goal.toleranceMinutes,
            allowsSplitSleep: goal.allowsSplitSleep,
            rephaseStepMinutes: goal.rephaseStepMinutes
        )
    }

    func toSleepGoal() -> SleepGoal {
        SleepGoal(
            mode: CoachMode(rawValue: mode) ?? .generalHealth,
            targetBedHour: targetBedHour,
            targetWakeHour: targetWakeHour,
            targetDuration: targetDuration,
            toleranceMinutes: toleranceMinutes,
            allowsSplitSleep: allowsSplitSleep,
            rephaseStepMinutes: rephaseStepMinutes
        )
    }
}
```

- [ ] **Step 6: Create SDPredictionMetrics and SDTrainingMetrics**

```swift
// spiral journey project/Models/SDPredictionMetrics.swift
import Foundation
import SwiftData

@Model
final class SDPredictionMetrics {
    var id: UUID
    var date: Date
    var mae: Double
    var accuracy: Double
    var sampleCount: Int

    init(id: UUID = UUID(), date: Date, mae: Double, accuracy: Double, sampleCount: Int) {
        self.id = id
        self.date = date
        self.mae = mae
        self.accuracy = accuracy
        self.sampleCount = sampleCount
    }
}
```

```swift
// spiral journey project/Models/SDTrainingMetrics.swift
import Foundation
import SwiftData

@Model
final class SDTrainingMetrics {
    var id: UUID
    var date: Date
    var preMae: Double
    var postMae: Double
    var trainCount: Int
    var validationCount: Int
    var accepted: Bool

    init(id: UUID = UUID(), date: Date, preMae: Double, postMae: Double,
         trainCount: Int, validationCount: Int, accepted: Bool) {
        self.id = id
        self.date = date
        self.preMae = preMae
        self.postMae = postMae
        self.trainCount = trainCount
        self.validationCount = validationCount
        self.accepted = accepted
    }
}
```

- [ ] **Step 7: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add spiral\ journey\ project/Models/SD*.swift
git commit -m "feat: add SwiftData models for all persisted entities

SDSleepEpisode, SDCircadianEvent, SDPredictionResult, SDCoachMessage,
SDUserGoal, SDPredictionMetrics, SDTrainingMetrics. String raw values
for enums. Converters to/from SpiralKit types."
```

---

### Task 5: ModelContainer Setup

**Files:**
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Add SwiftData import and ModelContainer**

```swift
import SwiftData

// Add to spiral_journey_projectApp struct, alongside existing @State properties:
@State private var modelContainer: ModelContainer = {
    let schema = Schema([
        SDSleepEpisode.self, SDCircadianEvent.self, SDPredictionResult.self,
        SDCoachMessage.self, SDUserGoal.self, SDPredictionMetrics.self,
        SDTrainingMetrics.self,
    ])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
        // Local-only: no CloudKit container. CKSyncEngine handles cloud sync.
    )
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Failed to create ModelContainer: \(error)")
    }
}()
```

**Note:** Use `@State` with a closure initializer. Keep the existing `init()` with `BackgroundTaskManager.registerTasks(store: store)` unchanged.

- [ ] **Step 2: Inject into view hierarchy**

Add `.modelContainer(modelContainer)` after existing `.environment()` modifiers:

```swift
ContentView()
    .environment(store)
    .environment(healthKit)
    .environment(calendarManager)
    .environment(llmService)
    // ... existing modifiers ...
    .modelContainer(modelContainer)
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: configure SwiftData ModelContainer at app entry point

Local-only ModelConfiguration. CKSyncEngine preserved for CloudKit.
All 7 SD model types registered."
```

---

### Task 6: Migration Service

**Files:**
- Create: `spiral journey project/Services/DataMigrationService.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Create DataMigrationService**

```swift
// spiral journey project/Services/DataMigrationService.swift
import Foundation
import SwiftData
import SpiralKit

@MainActor
final class DataMigrationService {

    private static let migrationKey = "swiftDataMigrationCompleted"
    private static let migrationVersionKey = "swiftDataMigrationVersion"
    private static let currentVersion = 1

    static var isMigrationNeeded: Bool {
        let defaults = UserDefaults.standard
        return !defaults.bool(forKey: migrationKey)
            || defaults.integer(forKey: migrationVersionKey) < currentVersion
    }

    static func migrateIfNeeded(
        from store: SpiralStore,
        into context: ModelContext
    ) throws -> MigrationResult? {
        guard isMigrationNeeded else { return nil }

        let sourceEpisodes = store.sleepEpisodes
        let sourceEvents = store.events
        let sourcePredictions = store.predictionHistory
        let sourceChat = store.chatHistory
        let sourceGoal = store.sleepGoal

        guard !sourceEpisodes.isEmpty || !sourceEvents.isEmpty else {
            markComplete()
            return MigrationResult(episodes: 0, events: 0, predictions: 0, messages: 0)
        }

        // Migrate episodes
        for episode in sourceEpisodes {
            context.insert(SDSleepEpisode(from: episode))
        }

        // Migrate events
        for event in sourceEvents {
            context.insert(SDCircadianEvent(from: event))
        }

        // Migrate prediction history
        for prediction in sourcePredictions {
            context.insert(SDPredictionResult(from: prediction))
        }

        // Migrate chat history
        for message in sourceChat {
            context.insert(SDCoachMessage(
                timestamp: message.timestamp,
                role: message.role.rawValue,
                content: message.content
            ))
        }

        // Migrate goal
        context.insert(SDUserGoal(from: sourceGoal))

        try context.save()

        // Verify episodes
        let episodeDescriptor = FetchDescriptor<SDSleepEpisode>(
            sortBy: [SortDescriptor(\.start)]
        )
        let migratedEpisodes = try context.fetch(episodeDescriptor)

        guard migratedEpisodes.count == sourceEpisodes.count else {
            throw MigrationError.countMismatch(
                entity: "SleepEpisode",
                expected: sourceEpisodes.count,
                got: migratedEpisodes.count
            )
        }

        // Spot-check first/last episode values
        if let firstSrc = sourceEpisodes.sorted(by: { $0.start < $1.start }).first,
           let firstMig = migratedEpisodes.first {
            guard abs(firstSrc.start - firstMig.start) < 0.001 else {
                throw MigrationError.dataCorruption(
                    detail: "First episode start mismatch"
                )
            }
        }

        // Verify events
        let eventDescriptor = FetchDescriptor<SDCircadianEvent>()
        let migratedEvents = try context.fetch(eventDescriptor)
        guard migratedEvents.count == sourceEvents.count else {
            throw MigrationError.countMismatch(
                entity: "CircadianEvent",
                expected: sourceEvents.count,
                got: migratedEvents.count
            )
        }

        markComplete()
        let result = MigrationResult(
            episodes: sourceEpisodes.count,
            events: sourceEvents.count,
            predictions: sourcePredictions.count,
            messages: sourceChat.count
        )
        print("[Migration] Success: \(result)")
        return result
    }

    private static func markComplete() {
        UserDefaults.standard.set(true, forKey: migrationKey)
        UserDefaults.standard.set(currentVersion, forKey: migrationVersionKey)
    }

    struct MigrationResult: CustomStringConvertible {
        let episodes: Int
        let events: Int
        let predictions: Int
        let messages: Int
        var description: String {
            "\(episodes) episodes, \(events) events, \(predictions) predictions, \(messages) messages"
        }
    }

    enum MigrationError: Error, LocalizedError {
        case countMismatch(entity: String, expected: Int, got: Int)
        case dataCorruption(detail: String)
        var errorDescription: String? {
            switch self {
            case .countMismatch(let e, let exp, let got): "Migration \(e) count mismatch: \(exp) → \(got)"
            case .dataCorruption(let d): "Migration corruption: \(d)"
            }
        }
    }
}
```

- [ ] **Step 2: Call migration from app entry point**

In `spiral_journey_projectApp.swift`, add a `.task` modifier:

```swift
.task {
    if DataMigrationService.isMigrationNeeded {
        do {
            let result = try DataMigrationService.migrateIfNeeded(
                from: store, into: modelContainer.mainContext
            )
            if let result { print("[App] Migrated: \(result)") }
        } catch {
            print("[App] Migration failed: \(error). Will retry next launch.")
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add spiral\ journey\ project/Services/DataMigrationService.swift \
      spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: add JSON→SwiftData migration service

Migrates episodes, events, predictions, chat, and goal from
UserDefaults. Verifies counts + spot-checks values. Retries on failure."
```

---

### Task 7: WatchSyncBridge

**Files:**
- Create: `spiral journey project/Services/WatchSyncBridge.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Create WatchSyncBridge**

Since `ModelContext.didSave` does not exist in SwiftData, we use `NotificationCenter` with `.NSPersistentStoreRemoteChange` or call the bridge explicitly from save points.

The simplest reliable approach: the bridge exposes a `syncEpisodes(context:)` method, called after any SwiftData save that modifies episodes.

```swift
// spiral journey project/Services/WatchSyncBridge.swift
import Foundation
import SwiftData
import SpiralKit

@MainActor
final class WatchSyncBridge {

    private let appGroupID: String

    init(appGroupID: String) {
        self.appGroupID = appGroupID
    }

    /// Call after any SwiftData save that modifies episodes.
    func syncEpisodes(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<SDSleepEpisode>(
                sortBy: [SortDescriptor(\.start)]
            )
            let episodes = try context.fetch(descriptor)
            let spiralKitEpisodes = episodes.map { $0.toSleepEpisode() }

            guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
            let data = try JSONEncoder().encode(spiralKitEpisodes)
            defaults.set(data, forKey: "episodes")
        } catch {
            print("[WatchSyncBridge] Failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Initialize in app entry point**

```swift
// Add property:
@State private var watchBridge: WatchSyncBridge?

// In .task {}, after migration:
watchBridge = WatchSyncBridge(appGroupID: SpiralStore.appGroupID)
```

- [ ] **Step 3: Build and commit**

```bash
git add spiral\ journey\ project/Services/WatchSyncBridge.swift \
      spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: add WatchSyncBridge for episode sync

Syncs SDSleepEpisode data to App Group UserDefaults for Watch.
Called explicitly from save points."
```

---

### Task 8: SpiralStore SwiftData Integration (Incremental)

**Files:**
- Modify: `spiral journey project/Services/SpiralStore.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Add ModelContext to SpiralStore**

```swift
import SwiftData

// Add to SpiralStore:
var modelContext: ModelContext?

func configure(with context: ModelContext) {
    self.modelContext = context
}
```

- [ ] **Step 2: Add SwiftData episode loading with cache**

```swift
private var cachedEpisodes: [SleepEpisode]?

func loadEpisodesFromSwiftData() -> [SleepEpisode]? {
    if let cached = cachedEpisodes { return cached }
    guard let context = modelContext else { return nil }
    do {
        let descriptor = FetchDescriptor<SDSleepEpisode>(
            sortBy: [SortDescriptor(\.start)]
        )
        let sdEpisodes = try context.fetch(descriptor)
        guard !sdEpisodes.isEmpty else { return nil }
        let result = sdEpisodes.map { $0.toSleepEpisode() }
        cachedEpisodes = result
        return result
    } catch {
        print("[SpiralStore] SwiftData fetch failed: \(error)")
        return nil
    }
}

func invalidateEpisodeCache() {
    cachedEpisodes = nil
}
```

- [ ] **Step 3: Use SwiftData episodes in recompute() when available**

In `recompute()`, at the line where episodes are accessed (the `let eps = sleepEpisodes` or similar):

```swift
// BEFORE:
let eps = sleepEpisodes

// AFTER:
let eps = loadEpisodesFromSwiftData() ?? sleepEpisodes
```

- [ ] **Step 4: Remove prediction history 90-cap**

In `updatePrediction()` (line ~567-569), remove:
```swift
// DELETE these lines:
if predictionHistory.count > 90 {
    predictionHistory = Array(predictionHistory.suffix(90))
}
```

Also check `appendBootstrappedPredictions` for a similar cap and remove if present.

- [ ] **Step 5: Inject ModelContext from app entry point**

In `spiral_journey_projectApp.swift`, in the `.task {}` block after migration:

```swift
store.configure(with: modelContainer.mainContext)
```

- [ ] **Step 6: Build and test**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add spiral\ journey\ project/Services/SpiralStore.swift \
      spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: add SwiftData episode loading to SpiralStore

Reads from SwiftData when available, falls back to UserDefaults.
In-memory cache for performance. Prediction history 90-cap removed."
```

---

## Chunk 3: Phase 3 — Coach Dual-Path

### Task 9: CoachLLMProvider Protocol

**Files:**
- Create: `spiral journey project/Services/Coach/CoachLLMProvider.swift`

- [ ] **Step 1: Define protocol and state enum**

```swift
// spiral journey project/Services/Coach/CoachLLMProvider.swift
import Foundation

protocol CoachLLMProvider: Sendable {
    var isAvailable: Bool { get }
    var displayName: String { get }
    var requiresDownload: Bool { get }
    var providerState: CoachProviderState { get }
    func generate(prompt: String, systemContext: String) async throws -> AsyncThrowingStream<String, Error>
}

enum CoachProviderState: Sendable {
    case ready
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case error(String)
}

enum CoachLLMError: Error, LocalizedError {
    case unavailable
    case generationFailed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Language model not available on this device"
        case .generationFailed(let msg): "Generation failed: \(msg)"
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add spiral\ journey\ project/Services/Coach/CoachLLMProvider.swift
git commit -m "feat: add CoachLLMProvider protocol with async throwing stream"
```

---

### Task 10: PhiLLMProvider

**Files:**
- Create: `spiral journey project/Services/Coach/PhiLLMProvider.swift`

- [ ] **Step 1: Create PhiLLMProvider wrapping LLMService**

Note: `LLMService.generate()` returns `async -> String` (does not throw). The provider wraps it in an AsyncThrowingStream, yielding the complete response as a single chunk (Phi-3.5 does its own internal streaming via the `streamingText` property).

```swift
// spiral journey project/Services/Coach/PhiLLMProvider.swift
import Foundation

@MainActor
@Observable
final class PhiLLMProvider: CoachLLMProvider {

    nonisolated var isAvailable: Bool { true }
    nonisolated var displayName: String { "Phi-3.5" }
    nonisolated var requiresDownload: Bool { true }

    private let llmService: LLMService

    var providerState: CoachProviderState {
        switch llmService.state {
        case .ready: .ready
        case .notDownloaded: .notDownloaded
        case .downloading(let p): .downloading(progress: p)
        case .loading, .downloaded: .loading
        case .error(let msg): .error(msg)
        }
    }

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    nonisolated func generate(
        prompt: String,
        systemContext: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let response = await self.llmService.generate(
                    prompt: prompt, systemContext: systemContext
                )
                if response.isEmpty {
                    continuation.finish(throwing: CoachLLMError.generationFailed("Empty response"))
                } else {
                    continuation.yield(response)
                    continuation.finish()
                }
            }
        }
    }

    func downloadModel() async { await llmService.downloadModel() }
    func loadModel() async { await llmService.loadModel() }
    func unloadModel() { llmService.unloadModel() }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add spiral\ journey\ project/Services/Coach/PhiLLMProvider.swift
git commit -m "feat: add PhiLLMProvider wrapping LLMService

Adapts Phi-3.5 GGUF to CoachLLMProvider protocol. Yields complete
response as single chunk. Empty response throws error."
```

---

### Task 11: FoundationModelsProvider

**Files:**
- Create: `spiral journey project/Services/Coach/FoundationModelsProvider.swift`

- [ ] **Step 1: Create provider with correct Foundation Models API**

```swift
// spiral journey project/Services/Coach/FoundationModelsProvider.swift
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class FoundationModelsProvider: CoachLLMProvider {

    nonisolated var displayName: String { "On-device AI" }
    nonisolated var requiresDownload: Bool { false }

    nonisolated var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    var providerState: CoachProviderState {
        isAvailable ? .ready : .error("Foundation Models not available")
    }

    nonisolated func generate(
        prompt: String,
        systemContext: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.isAvailable else {
            throw CoachLLMError.unavailable
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession {
                        systemContext
                    }

                    // Use streamResponse for true token-level streaming
                    let stream = session.streamResponse(to: prompt)
                    var lastContent = ""
                    for try await snapshot in stream {
                        // snapshot.content is progressively built — yield only the delta
                        let newContent = snapshot.content
                        if newContent.count > lastContent.count {
                            let delta = String(newContent.dropFirst(lastContent.count))
                            continuation.yield(delta)
                            lastContent = newContent
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        #else
        throw CoachLLMError.unavailable
        #endif
    }
}
```

**Note:** Verify the exact `LanguageModelSession` and `streamResponse` API against the iOS 26 SDK at implementation time. Use `@apple-on-device-ai` skill for current reference.

- [ ] **Step 2: Build** (compiles with #if canImport guard on pre-iOS 26 SDK)

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add spiral\ journey\ project/Services/Coach/FoundationModelsProvider.swift
git commit -m "feat: add FoundationModelsProvider for iOS 26+

Uses SystemLanguageModel.default.isAvailable for runtime hardware
check. True token-level streaming via streamResponse(to:).
Gated with #if canImport(FoundationModels)."
```

---

### Task 12: Provider Factory & CoachChatView Integration

**Files:**
- Create: `spiral journey project/Services/Coach/CoachProviderFactory.swift`
- Modify: `spiral journey project/Views/Coach/CoachChatView.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Create factory**

```swift
// spiral journey project/Services/Coach/CoachProviderFactory.swift
import Foundation

@MainActor
struct CoachProviderFactory {
    static func makeProvider(llmService: LLMService) -> any CoachLLMProvider {
        let fm = FoundationModelsProvider()
        if fm.isAvailable { return fm }
        return PhiLLMProvider(llmService: llmService)
    }
}
```

- [ ] **Step 2: Update CoachChatView to use provider**

The key changes in `CoachChatView.swift`:

Replace `@Environment(LLMService.self) private var llm` with provider injection (via init parameter or environment). Update the generate call:

```swift
// BEFORE:
let response = await llm.generate(prompt: userMessage, systemContext: systemPrompt)
messages.append(ChatMessage(role: .assistant, content: response))

// AFTER:
do {
    var responseText = ""
    let stream = try await provider.generate(prompt: userMessage, systemContext: systemPrompt)
    // Add streaming message placeholder
    messages.append(ChatMessage(role: .assistant, content: ""))
    for try await chunk in stream {
        responseText += chunk
        // Update last message with accumulated text
        messages[messages.count - 1] = ChatMessage(role: .assistant, content: responseText)
    }
} catch {
    messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
}
```

Update UI states:
```swift
// Show download UI only if provider needs it:
if provider.requiresDownload {
    switch provider.providerState {
    case .notDownloaded: // show download button
    case .downloading(let p): // show progress
    // etc.
    }
} else {
    // Foundation Models: ready immediately, show chat
}

// Provider indicator:
Text(provider.displayName)
    .font(.caption2)
    .foregroundStyle(.secondary)
```

- [ ] **Step 3: Wire up in app entry point**

In `spiral_journey_projectApp.swift`:

```swift
// Add property:
@State private var coachProvider: (any CoachLLMProvider)?

// In .task {}:
coachProvider = CoachProviderFactory.makeProvider(llmService: llmService)
```

Pass to CoachChatView via init or environment.

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add spiral\ journey\ project/Services/Coach/CoachProviderFactory.swift \
      spiral\ journey\ project/Views/Coach/CoachChatView.swift \
      spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: integrate CoachLLMProvider into chat view

Runtime selection: Foundation Models (iOS 26+) or Phi-3.5 fallback.
Streaming response display. Provider name shown in UI.
Download flow only shown when provider requires it."
```

---

### Task 13: System Prompt Enhancements

**Files:**
- Modify: `spiral journey project/Services/LLMContextBuilder.swift`

- [ ] **Step 1: Add provider-aware prompt building**

```swift
// Add to LLMContextBuilder:

enum PromptCapability {
    case compact  // Phi-3.5: current prompt size
    case rich     // Foundation Models: more context
}

/// Enhanced prompt with prediction data for capable providers.
static func buildSystemPrompt(
    analysis: AnalysisResult,
    goal: SleepGoal,
    records: [SleepRecord],
    locale: Locale,
    capability: PromptCapability,
    prediction: PredictionOutput? = nil,
    modelAccuracy: Double? = nil
) -> String {
    var prompt = buildSystemPrompt(
        analysis: analysis, goal: goal, records: records, locale: locale
    )

    if capability == .rich, let prediction {
        let bedStr = String(format: "%02d:%02d",
            Int(prediction.predictedBedtimeHour),
            Int((prediction.predictedBedtimeHour.truncatingRemainder(dividingBy: 1)) * 60))
        prompt += "\n\nTonight's prediction: bedtime \(bedStr)."
        if let acc = modelAccuracy {
            prompt += " Model accuracy this week: \(Int(acc * 100))%."
        }
    }

    return prompt
}

/// Provider-aware history size.
static func maxHistoryMessages(for capability: PromptCapability) -> Int {
    switch capability {
    case .compact: 10  // Phi-3.5 library truncates internally to 4
    case .rich: 10     // Foundation Models handles larger context
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add spiral\ journey\ project/Services/LLMContextBuilder.swift
git commit -m "feat: add provider-aware system prompt tiers

Rich tier includes tonight's prediction and model accuracy.
Compact tier unchanged. Avoids double-truncation with Phi-3.5."
```

---

## Chunk 4: Phase 4 — Robustness & Quality

### Task 14: Improved Synthetic Training Data

**Files:**
- Modify: `Scripts/train_sleep_model.py`
- Modify: `Scripts/train_updatable_model.py`

- [ ] **Step 1: Update data generation with chronotype subpopulations**

In both Python scripts, replace the data generation function:

```python
import numpy as np

def generate_synthetic_data(n_samples=10000, seed=42):
    rng = np.random.default_rng(seed)

    # Chronotype subpopulations
    chronotypes = rng.choice(
        ['owl', 'intermediate', 'lark'],
        size=n_samples,
        p=[0.30, 0.50, 0.20]
    )

    base_bedtimes = {'owl': 25.5, 'intermediate': 23.5, 'lark': 22.0}
    bedtime_sd = {'owl': 1.0, 'intermediate': 0.7, 'lark': 0.5}

    targets = np.zeros(n_samples)
    # ... build features array with same 21 features as existing code ...
    # Key changes to target computation:

    for i in range(n_samples):
        ct = chronotypes[i]
        base = base_bedtimes[ct] + rng.normal(0, bedtime_sd[ct])

        # Correlated event effects
        caffeine_effect = features[i]['caffeine'] * rng.uniform(0.33, 0.67)
        exercise_effect = features[i]['exercise'] * rng.uniform(-0.33, -0.17)
        alcohol_effect = features[i]['alcohol'] * rng.uniform(0.25, 0.5)
        melatonin_effect = features[i]['melatonin'] * rng.uniform(-0.5, -0.25)
        debt_effect = -0.375 if features[i]['processS'] > 0.65 else 0.0

        targets[i] = np.clip(
            base + caffeine_effect + exercise_effect + alcohol_effect
            + melatonin_effect + debt_effect,
            20.0, 28.0
        )

    return features, targets
```

**Note:** Keep the existing 21-feature vector construction unchanged. Only modify the target generation and data distribution. The plan provides the key changes; adapt to the existing code structure.

- [ ] **Step 2: Regenerate models**

```bash
cd "/Users/xaron/Desktop/spiral journey project/Scripts" && python train_sleep_model.py && python train_updatable_model.py
```

- [ ] **Step 3: Build and commit**

```bash
git add Scripts/train_sleep_model.py Scripts/train_updatable_model.py \
      spiral\ journey\ project/Resources/SleepPredictor.mlmodel \
      spiral\ journey\ project/Resources/SleepPredictorUpdatable.mlmodel
git commit -m "feat: improve synthetic training data with chronotypes

30% owls / 50% intermediate / 20% larks. Correlated event effects.
Per-chronotype bedtime variance. Regenerated both CoreML models."
```

---

### Task 15: Prediction Metrics Tracker

**Files:**
- Create: `spiral journey project/Services/PredictionMetricsTracker.swift`

- [ ] **Step 1: Create tracker**

```swift
// spiral journey project/Services/PredictionMetricsTracker.swift
import Foundation
import SwiftData

@MainActor
final class PredictionMetricsTracker {

    enum MetricTrend: String, Sendable {
        case improving, stable, worsening
    }

    static func computeMetrics(
        from context: ModelContext
    ) throws -> (mae: Double, accuracy: Double, trend: MetricTrend)? {
        var descriptor = FetchDescriptor<SDPredictionResult>(
            predicate: #Predicate { $0.actualBedtime != nil },
            sortBy: [SortDescriptor(\.targetDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30

        let results = try context.fetch(descriptor)
        guard results.count >= 3 else { return nil }

        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recent = results.filter { $0.targetDate >= twoWeeksAgo }
        guard !recent.isEmpty else { return nil }

        let errors = recent.compactMap { $0.bedError }.map { abs($0) / 60.0 } // convert min→hours
        let mae = errors.reduce(0, +) / Double(errors.count)
        let withinThreshold = errors.filter { $0 <= 0.5 }.count // ±30min
        let accuracy = Double(withinThreshold) / Double(errors.count)

        let trend: MetricTrend
        if recent.count >= 6 {
            let mid = recent.count / 2
            let recentMAE = recent[0..<mid].compactMap { $0.bedError }
                .map { abs($0) / 60.0 }.reduce(0, +) / Double(mid)
            let olderMAE = recent[mid...].compactMap { $0.bedError }
                .map { abs($0) / 60.0 }.reduce(0, +) / Double(recent.count - mid)
            trend = recentMAE < olderMAE - 0.05 ? .improving :
                    recentMAE > olderMAE + 0.05 ? .worsening : .stable
        } else {
            trend = .stable
        }

        // Persist
        context.insert(SDPredictionMetrics(
            date: Date(), mae: mae, accuracy: accuracy, sampleCount: recent.count
        ))
        try context.save()

        return (mae, accuracy, trend)
    }
}
```

- [ ] **Step 2: Wire into coach prompt (in CoachChatView send flow)**

```swift
let metrics = try? PredictionMetricsTracker.computeMetrics(from: modelContext)
let capability: LLMContextBuilder.PromptCapability = provider.requiresDownload ? .compact : .rich
let prompt = LLMContextBuilder.buildSystemPrompt(
    analysis: analysis, goal: store.sleepGoal, records: records,
    locale: .current, capability: capability,
    prediction: store.latestPrediction,
    modelAccuracy: metrics?.accuracy
)
```

- [ ] **Step 3: Build and commit**

```bash
git add spiral\ journey\ project/Services/PredictionMetricsTracker.swift
git commit -m "feat: add PredictionMetricsTracker with rolling MAE

14-day rolling window, ±30min accuracy threshold, trend detection.
Persisted as SDPredictionMetrics. Fed into coach system prompt."
```

---

### Task 16: Data Retention Policies

**Files:**
- Create: `spiral journey project/Services/DataRetentionService.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Create DataRetentionService**

```swift
// spiral journey project/Services/DataRetentionService.swift
import Foundation
import SwiftData

@MainActor
final class DataRetentionService {

    static func enforce(context: ModelContext) throws {
        try trimChatHistory(context: context, maxMessages: 100)
        try trimOldMetrics(context: context, maxAgeDays: 90)
    }

    private static func trimChatHistory(context: ModelContext, maxMessages: Int) throws {
        let descriptor = FetchDescriptor<SDCoachMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        if all.count > maxMessages {
            for msg in all[maxMessages...] {
                context.delete(msg)
            }
            try context.save()
            print("[Retention] Trimmed \(all.count - maxMessages) old chat messages")
        }
    }

    private static func trimOldMetrics(context: ModelContext, maxAgeDays: Int) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date())!

        // Trim prediction metrics
        let pmDescriptor = FetchDescriptor<SDPredictionMetrics>(
            predicate: #Predicate { $0.date < cutoff }
        )
        let oldPM = try context.fetch(pmDescriptor)
        for m in oldPM { context.delete(m) }

        // Trim training metrics
        let tmDescriptor = FetchDescriptor<SDTrainingMetrics>(
            predicate: #Predicate { $0.date < cutoff }
        )
        let oldTM = try context.fetch(tmDescriptor)
        for m in oldTM { context.delete(m) }

        if !oldPM.isEmpty || !oldTM.isEmpty {
            try context.save()
            print("[Retention] Removed \(oldPM.count) prediction + \(oldTM.count) training metrics older than \(maxAgeDays)d")
        }
    }
}
```

- [ ] **Step 2: Call from app entry point**

In `spiral_journey_projectApp.swift` `.task {}`, after migration:

```swift
try? DataRetentionService.enforce(context: modelContainer.mainContext)
```

- [ ] **Step 3: Build and commit**

```bash
git add spiral\ journey\ project/Services/DataRetentionService.swift \
      spiral\ journey\ project/spiral_journey_projectApp.swift
git commit -m "feat: add data retention policies

Chat: keep last 100 messages. Prediction + training metrics: 90-day
window. Predictions kept forever (valuable for ML training)."
```

---

## Final Verification

After all tasks complete:

- [ ] **Full SpiralKit test suite:** `cd SpiralKit && swift test`
- [ ] **iOS build:** `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
- [ ] **Watch build:** `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS`
- [ ] **Run in simulator:** verify spiral rendering unaffected, coach works, predictions generate
- [ ] **Test migration:** launch with existing UserDefaults data, confirm SwiftData populated
- [ ] **Test regression guard:** manually trigger retraining with insufficient data, verify model reverts
