# ML & AI Coach Improvements — Design Spec

**Date:** 2026-03-16
**Status:** Approved
**Approach:** Prediction first → Storage → Coach (Enfoque A)

## Context

Spiral Journey has an ML sleep prediction pipeline (CoreML gradient boosting + updatable neural network + heuristic fallback) and an AI Coach chat (Phi-3.5-mini GGUF on-device). Both are functional but have gaps in validation, feature quality, storage scalability, and LLM modernization. The app is pre-release (single developer user), making this the ideal time for foundational improvements.

### Constraints

- **Compatibility:** iOS 18+ minimum. Foundation Models (iOS 26+) as enhancement, not requirement.
- **Privacy:** All processing on-device. No cloud dependencies.
- **Spiral is primary:** The coach is secondary/experimental. Improvements must not compromise the core spiral experience.
- **No existing users:** Free to make breaking storage changes with migration path.

---

## Phase 1: ML Pipeline Improvements

### 1.1 Validation in On-Device Retraining

**Problem:** `ModelTrainingService` uses all 50+ evaluated predictions for `MLUpdateTask` with no validation split. No way to detect overfitting or model degradation.

**Design:**

- Raise minimum samples from 50 to 60 (eligibility gate only — all available samples beyond 60 are used)
- Before training: shuffle all available evaluated samples, split 80/20 (e.g., 60 samples → 48 train / 12 validation; 100 samples → 80 train / 20 validation)
- Compute MAE on validation set with current model (pre-training baseline)
- Run `MLUpdateTask` with training set only
- Compute MAE on validation set with new model
- **Regression guard:** if new MAE ≥ old MAE, delete the personalized model file from `personalisedModelURL` on disk, call `MLPredictionEngine.reloadModel()`, log result, keep base model. This prevents the stale `.mlmodelc` from being loaded on next app launch.
- Store training metrics (pre/post MAE, sample count, date, accepted/rejected) in a `TrainingMetrics` record

**Files changed:** `ModelTrainingService.swift`, `MLPredictionEngine.swift` (expose reload)

### 1.2 Continuous Process S in Feature Builder

**Problem:** `PredictionFeatureBuilder` calls `TwoProcessModel.processS()` which resets each day (no carry-over). `computeContinuous()` exists but is unused in feature engineering — it tracks cumulative sleep debt across days.

**Design:**

- Replace `processS()` call with `computeContinuous()` fed the last 7 days of sleep records
- `computeContinuous()` returns `[TwoProcessPoint]` with hourly S values across all input days. Extract the S value from the **last element** of the returned array (representing the most recent computed hour). If the current time is mid-day, truncate the last day's computation to the current hour.
- Handle sparse data: if hourly activity data is missing for some days, fill gaps with wake-state assumption (conservative — S decays toward baseline). Log a warning if >2 days have no activity data.
- This captures real accumulated sleep debt (e.g., 3 short nights → elevated S) vs. the current daily-reset snapshot
- No changes to other 20 features
- Retrain Python models with updated synthetic data that reflects continuous S behavior

**Files changed:** `PredictionFeatureBuilder.swift`, `TwoProcessModel.swift` (sparse data handling)

### 1.3 Circular Difference for Wake Time Evaluation

**Problem:** `evaluatePastPredictions()` uses circular difference for bedtime but linear difference for wake. Wake can cross midnight (e.g., predicted 23:30 vs actual 00:15 = 45 min error, not 23h 15min).

**Design:**

- Apply the same circular difference logic (±12h wrap) to wake time comparison
- Extract circular difference into a shared helper function used by both bed and wake evaluation

**Files changed:** `PredictionModels.swift` (in SpiralKit — where `circularDiff()` and `evaluate()` live)

---

## Phase 2: SwiftData Migration

### 2.1 Data Models

The primary persisted entity in the current codebase is `SleepEpisode` (raw sleep intervals with start/end absolute hours, source, HealthKit sample ID). `SleepRecord` is a **computed/derived** struct generated on each `recompute()` call — it should remain computed, not persisted.

Convert existing persisted `Codable` structs to `@Model` classes:

| Model | Key Properties | Relationships |
|-------|---------------|---------------|
| `SDSleepEpisode` | start, end, source, healthKitSampleID, phase, modifiedAt (new — for change tracking in WatchSyncBridge and CloudSyncManager conflict resolution) | standalone |
| `SDCircadianEvent` | absoluteHour, type, amount | standalone (matched to episodes by absoluteHour range at query time, as current code does) |
| `SDPredictionResult` | targetDate, predicted, actual, error, engineType | standalone |
| `SDCoachMessage` | timestamp, role, content | standalone |
| `SDUserGoal` | mode, targetBed, targetWake, targetDuration | standalone |
| `SDPredictionMetrics` | date, mae, accuracy, sampleCount | standalone |
| `SDTrainingMetrics` | date, preMae, postMae, sampleCount, accepted | standalone |

`SleepRecord` remains a computed struct derived from `SDSleepEpisode` data via `ManualDataConverter.convert()`, preserving the existing architecture.

Prefix `SD` to avoid collision with existing structs during migration period.

### 2.2 ModelContainer Setup

- Configure `ModelContainer` at app entry point with all model types
- **Local-only `ModelConfiguration`** — no CloudKit container ID. The existing `CKSyncEngine`-based `CloudSyncManager` is preserved as the sync layer (it has mature conflict resolution with last-writer-wins and HealthKit dedup). SwiftData + CloudKit's `NSPersistentCloudKitContainer` would conflict with `CKSyncEngine`, causing duplicate records and sync corruption.
- `CloudSyncManager` writes to SwiftData locally when CloudKit events arrive, instead of writing to UserDefaults directly
- Inject `ModelContainer` via `.modelContainer()` modifier
- Services receive `ModelContext` parameter instead of reading `SpiralStore`
- Views use `@Query` for reactive data

### 2.3 Migration from JSON/UserDefaults

- On first launch: detect existing UserDefaults data via a `migrationCompleted` flag
- Read → deserialize JSON → insert into SwiftData
- **Verification:** compare record counts AND spot-check first/last record dates and values (not just counts). Explicitly map enum types (`DataSource`, `ChatRole`) and optional fields (`healthKitSampleID`) during conversion.
- Mark migration complete with a flag in UserDefaults
- Delete old JSON only after successful verification
- If migration fails: keep JSON, retry next launch, log error with details

### 2.4 SpiralStore Simplification

`SpiralStore` becomes a lightweight session coordinator:

- No longer persists sleep/prediction/coach data
- Retains: cursor position, zoom level, UI configuration, transient state
- Computed properties (cosinor, current prediction) recalculated from SwiftData queries
- `recompute()` reads from SwiftData instead of internal arrays
- **Performance note:** SwiftData queries hit SQLite (I/O-bound) vs. current in-memory arrays. To avoid slowing `recompute()` (which runs on every episode change and foreground event), cache the most recent query results in memory and invalidate on SwiftData save notifications. Profile before and after migration to ensure no regression.

### 2.5 Watch App Sync

- SwiftData does not sync to watchOS directly
- Maintain App Group `UserDefaults` bridge for Watch
- **Observer pattern:** implement a `WatchSyncBridge` service that observes SwiftData save notifications (via `ModelContext.willSave` / `NotificationCenter`) and automatically mirrors `SDSleepEpisode` changes to shared UserDefaults. This prevents relying on call-site discipline where every write path must remember to also update UserDefaults.
- Watch reads from UserDefaults as before — no Watch-side changes
- Remove existing prediction history 90-cap in `SpiralStore.updatePrediction()` — SwiftData handles storage efficiently and all predictions are valuable for training

---

## Phase 3: Coach — Foundation Models + Phi-3.5 Fallback

### 3.1 Provider Protocol

```swift
protocol CoachLLMProvider {
    var isAvailable: Bool { get }
    var displayName: String { get }
    func generate(prompt: String, systemContext: String) async throws -> AsyncThrowingStream<String, Error>
}
```

The method is `async throws` returning `AsyncThrowingStream` to uniformly handle Foundation Models errors and Phi-3.5 load failures.

Runtime selection: `#available(iOS 26, *)` AND `SystemLanguageModel.isAvailable` (runtime hardware check). If the device runs iOS 26+ but lacks the hardware (pre-A17 Pro), fall back to `PhiLLMProvider`. The chat view and `LLMContextBuilder` remain unchanged — only the inference backend swaps.

### 3.2 Foundation Models Provider (iOS 26+)

- Uses `SystemLanguageModel` — no download, no KV cache management
- Runtime check: `SystemLanguageModel.isAvailable` before attempting to create session (device may run iOS 26 but lack A17 Pro / M-series hardware)
- `LanguageModelSession` with system prompt from existing `LLMContextBuilder`
- Native async streaming via `respond(to:)`
- No memory warning handling needed (system-managed)
- Optional future: `@Generable` for structured coach responses (not in v1)

### 3.3 Phi-3.5 Fallback Provider (iOS 18-25)

- Current `LLMService` refactored to conform to `CoachLLMProvider`
- Token-buffering approach adapted to produce `AsyncThrowingStream<String, Error>`
- No functional changes — same download, inference, memory management
- Encapsulated as `PhiLLMProvider`
- Note: Phi-3.5's internal `historyLimit = 4` handles its own truncation. The `LLMContextBuilder` should pass full history and let each provider truncate as needed, avoiding double-truncation.

### 3.4 System Prompt Enhancements

Tiered prompt complexity based on backend capability:

| Aspect | Foundation Models (iOS 26+) | Phi-3.5 (iOS 18-25) |
|--------|---------------------------|---------------------|
| Message history | 10 messages (managed by LLMContextBuilder) | Full history passed, Phi-3.5 truncates internally to 4 |
| Prediction data in prompt | Yes (tonight's prediction + model accuracy) | No (token budget too tight) |
| Prompt detail | Rich context | Compact (current) |

### 3.5 UI Changes

- iOS 26+: no download/load flow — coach is instantly available
- iOS 18-25: current flow preserved (download → load → chat)
- Subtle indicator of backend in use ("On-device AI" vs "Phi-3.5")
- No other UI changes

---

## Phase 4: Robustness & Quality

### 4.1 Improved Synthetic Training Data

Update Python training scripts:

- **Chronotype subpopulations:** ~30% night owls (mean bedtime 01:30), ~50% intermediate (23:30), ~20% early birds (22:00)
- **Feature correlations:** caffeine → +20-40 min bedtime, exercise → -10-20 min, alcohol → +15-30 min, previous short sleep → earlier bedtime (debt pressure)
- **Realistic noise:** Gaussian noise on targets, ~15-30 min SD per person
- Regenerate both `SleepPredictor.mlmodel` and `SleepPredictorUpdatable.mlmodel`

### 4.2 Prediction Metrics Tracker

- `PredictionMetricsTracker` computes: rolling 14-day MAE, accuracy (% within ±30 min), trend (improving/worsening)
- Persisted as `SDPredictionMetrics` in SwiftData
- Injected into coach system prompt: "model accuracy this week: 73%, average error: ±18 min"
- Available in debug UI for developer monitoring

### 4.3 Data Retention Policies

With SwiftData:

- **Predictions:** keep all (remove existing 90-cap from `SpiralStore.updatePrediction()`; ~1/day is negligible storage and all are valuable for training)
- **Chat history:** keep last 100 messages, trim older
- **Detailed metrics:** 90-day rolling window, aggregate older into weekly summaries
- Cleanup runs on app launch, background task, or after SwiftData save

---

## Implementation Order

```
Phase 1 (ML fixes)          ~3 changes, surgical
  1.1 Validation split
  1.2 computeContinuous()
  1.3 Circular wake diff
         ↓
Phase 2 (SwiftData)          largest change, foundational
  2.1 Data models
  2.2 Container setup (local-only, keep CKSyncEngine)
  2.3 Migration
  2.4 SpiralStore simplification
  2.5 Watch bridge (observer pattern)
         ↓
Phase 3 (Coach)              depends on Phase 2 for data access
  3.1 Provider protocol (async throws)
  3.2 Foundation Models (with hardware check)
  3.3 Phi-3.5 refactor
  3.4 Prompt enhancements
  3.5 UI adjustments
         ↓
Phase 4 (Robustness)         polish, depends on Phase 2 for storage
  4.1 Training data
  4.2 Metrics tracker
  4.3 Retention policies
```

## Testing Strategy

- **Phase 1:** Unit tests for validation split logic, continuous S computation, circular difference helper. Regression guard test (verify stale model file is deleted).
- **Phase 2:** Migration tests (mock JSON → SwiftData with enum mapping verification), integration tests for queries, performance profiling of `recompute()` before/after.
- **Phase 3:** Protocol conformance tests, mock providers for UI testing, Foundation Models availability fallback test.
- **Phase 4:** Metrics calculation tests, retention policy tests, synthetic data distribution validation.
