# SleepDNA Engine — Design Spec

**Date:** 2026-03-17
**Status:** Approved (v2 — merged with clinical/geometric foundations)
**Scope:** Sub-project 1 of 3 (Engine → 3D Visualization → Insights UI)

## Context

Spiral Journey models sleep as a spiral. This spec extends the model with a double-helix DNA architecture: two interleaved strands encoding heterogeneous data sources with phase-synchrony analysis ("base pairs"). The engine encodes daily data as "nucleotides", groups them into weekly "sequences", and uses Dynamic Time Warping (DTW) to find similar weeks, discover recurring motifs ("genes"), classify deviations ("mutations"), detect health markers, and predict future sleep by sequence alignment.

### Goals

- Detect invisible patterns that day-by-day analysis misses (hidden cycles, delayed triggers, week-type clusters, predictive transitions)
- Provide a third prediction engine alongside ML (NN/GB) and heuristic
- Work from day 1 with graceful tier degradation (<4 weeks → 4-8 → 8+)
- Produce a unique, publishable scoring matrix (SleepBLOSUM) personalized per user
- Detect clinical markers: circadian anarchy, fragmentation, phase drift severity
- Feed insights into the AI coach, 3D visualization, and health alerts

### Constraints

- Module lives in SpiralKit (shared by iOS and Watch — engine runs on both, 3D view is iOS-only)
- Reads from existing data types (SleepRecord, CircadianEvent, CosinorResult, TwoProcessModel)
- Requires refactoring PredictionService to support pluggable engines (Step 0)
- DTW computation runs on background thread, cached, recalculated only on new data
- Cancellation: new data arriving mid-computation cancels in-flight DTW and restarts
- Privacy: all computation on-device, no cloud

---

## 0. Prerequisite: PredictionService Refactoring

The current `PredictionService` is a hardcoded if/else between ML and heuristic engines. To support a third engine with ensemble weighting, it must be refactored:

1. Define `PredictionEngineProtocol`:
```swift
protocol PredictionEngineProtocol {
    var engineType: PredictionEngine { get }
    func predict(from input: PredictionInput, targetDate: Date) -> PredictionOutput?
}
```

2. Add `.sequenceAlignment` case to `PredictionEngine` enum (requires SwiftData migration consideration — new case is additive, old cases decode normally)

3. Refactor `PredictionService.generatePrediction()` from if/else to loop-and-combine:
   - Run all registered engines
   - Combine via weighted average (adaptive weights per engine)
   - Store per-engine output for accuracy tracking

This refactoring is a prerequisite step before the alignment engine can integrate.

---

## 1. Nucleotide Encoding

Each day is encoded as a normalized vector — a "nucleotide". Uses sin/cos encoding for circular features (produces 2 values per circular feature for proper distance computation in DTW).

### Strand 1 — Sleep (intrinsic, 8 values)

| # | Feature | Source | Encoding |
|---|---------|--------|----------|
| 1-2 | bedtimeHour | SleepRecord.bedtimeHour | sin(2πh/24), cos(2πh/24) |
| 3-4 | wakeupHour | SleepRecord.wakeupHour | sin(2πh/24), cos(2πh/24) |
| 5 | sleepDuration | SleepRecord.sleepDuration | /12h → [0,1] |
| 6 | processS | PredictionFeatureBuilder.continuousProcessS() | already [0,1] |
| 7 | cosinorAcrophase | CosinorResult.acrophase | /24 → [0,1] |
| 8 | cosinorR² | CosinorResult.r2 | already [0,1] |

### Strand 2 — Context (extrinsic, 8 values)

| # | Feature | Source | Encoding |
|---|---------|--------|----------|
| 9 | caffeine | CircadianEvent count (type: .caffeine) | /5 → [0,1] (fixed max=5) |
| 10 | exercise | CircadianEvent count (type: .exercise) | 0 or 1 |
| 11 | alcohol | CircadianEvent count (type: .alcohol) | /3 → [0,1] (fixed max=3) |
| 12 | melatonin | CircadianEvent count (type: .melatonin) | 0 or 1 |
| 13 | stress | CircadianEvent count (type: .stress) | /3 → [0,1] (fixed max=3) |
| 14 | isWeekend | SleepRecord.isWeekend | 0 or 1 |
| 15 | driftMinutes | SleepRecord.driftMinutes | /120 → clamp [-1,1] |
| 16 | sleepQuality | composite: duration_score × regularity × cosinorR² | [0,1] |

**Total: 16 features per nucleotide** (8 sleep + 8 context).

**Event-to-day mapping:** Events are matched to days by `absoluteHour` range `[day × period, (day+1) × period)` where `period` is sourced from SpiralStore (default 24.0), consistent with existing `PredictionFeatureBuilder` logic.

**Fixed normalization caps** (caffeine=5, alcohol=3, stress=3): values above the cap are clamped to 1.0. This prevents historical nucleotides from changing when new extremes appear, keeping cached DTW distances stable.

**Sleep quality metric** (feature 16): `min(duration / goalDuration, 1.0) × SRI_normalized × cosinorR²`. This is the target metric used throughout for mutation classification and SleepBLOSUM learning.

### Sequence

A `WeekSequence` = 7 consecutive `DayNucleotide` values = matrix 7×16.

---

## 2. Base Pairs — Hilbert Phase Synchrony

Instead of simple correlation (statistically meaningless with n=6 per day), base pairs use the **Hilbert Transform** to compute phase synchrony between the two strands over rolling windows.

### Algorithm

1. For each feature pair (strand 1 feature × strand 2 feature), extract the time series over a 14-day rolling window
2. Apply the Hilbert Transform to obtain the analytic signal and instantaneous phase for each
3. Compute the Phase Locking Value (PLV): `PLV = |mean(exp(i × Δθ(t)))|` where `Δθ(t)` is the instantaneous phase difference
4. PLV ∈ [0,1]: 0 = no synchrony, 1 = perfect phase lock

### Output

```swift
struct BasePairSynchrony {
    let sleepFeature: Int       // index in strand 1
    let contextFeature: Int     // index in strand 2
    let plv: Double             // phase locking value [0,1]
    let meanPhaseDiff: Double   // average phase offset (radians)
    let direction: PhaseDirection // .leading or .lagging
}
```

### Clinical Value

- High PLV between caffeine and bedtime delay → strong coupling (caffeine reliably shifts your sleep)
- Low PLV → decoupled (caffeine doesn't affect you much)
- The `meanPhaseDiff` reveals the **lag** — "caffeine affects your bedtime 2 days later, not same day"
- This replaces the vague "cross-strand correlation" from v1

### Visual Encoding in 3D

The PLV dictates the **angle of torsion** between the two helix strands. High synchrony = tight twist (strands close together). Low synchrony = loose twist (strands separate). This is the "twist rate" from the geometric grammar.

---

## 3. Helix Geometry (for 3D sub-project)

The engine computes geometric parameters that the 3D view will consume. Based on polar coordinate transformation:

### Coordinate Equations

```
r(t) = a + b·t                    // radius grows with time (avoids overlap)
θ(t) = 2π·t / T                   // T = period (1 day = 1440 minutes)
x = r(t) · cos(θ(t))
y = r(t) · sin(θ(t))
z = t                              // vertical axis = accumulated time
```

### Visual Grammar — Geometric Parameters per Day

| Parameter | Encodes | Computation |
|-----------|---------|-------------|
| **Twist rate** | Phase synchrony (PLV) | Rotation angle between strands = PLV × maxTwist |
| **Helix radius** | Phase misalignment severity | abs(midSleepDeviation) from chronotype optimal |
| **Strand thickness** | Sleep stage intensity | Deep sleep (N3) proportion × maxThickness |
| **Surface texture** | Fragmentation | Microawakening count → roughness parameter |

These parameters are computed by the engine and stored in `SleepDNAProfile.helixGeometry` for the 3D renderer.

---

## 4. Sequence Alignment (DTW)

### Algorithm

Dynamic Time Warping between two `WeekSequence` matrices (7×16). DTW finds the optimal alignment allowing temporal warping (a Monday pattern can match a Tuesday in another week).

**Distance function:** weighted Euclidean between two nucleotides, using SleepBLOSUM diagonal weights.

**Output:** DTW distance (lower = more similar) and the alignment path (which days matched).

### SleepBLOSUM — Adaptive Scoring Matrix

A diagonal weight vector of 16 doubles that personalizes DTW:

- **Initial:** equal weights (1.0) for all 16 features
- **Learned:** after 8+ weeks, compute mutual information between each feature and next-day sleep quality (feature 16). Features with higher predictive power get higher weight.
- **Updated:** weekly, alongside ML model retraining cycle (same cooldown)
- **Stored:** as a flat array of 16 doubles in SwiftData (`SDSleepBLOSUM`)
- **Diagonal-only:** captures per-feature importance, not cross-feature interactions. Cross-feature effects are captured by the Hilbert phase synchrony instead.

### Tier Degradation

| Data available | Method | Capabilities |
|---|---|---|
| <4 weeks | Day-to-day Hilbert synchrony between strands | Base pairs: "caffeine → bedtime +30min for you, 1-day lag" |
| 4-8 weeks | DTW on short windows (3-5 days) | Micro-patterns: "post-weekend you always sleep worse" |
| 8+ weeks | Full DTW + clustering + motif discovery | Cycles, clusters, transitions, prediction by alignment |

---

## 5. Pattern Detection

### Motif Discovery ("Genes")

1. Extract all sliding windows of 3-5 days from history
2. **Optimization:** Compute pairwise DTW on weekly windows only (52/year = 1,326 pairs, ~1.3s). For finer motifs, use random sampling of sub-weekly windows (cap at 200 comparisons).
3. Agglomerative clustering on the distance matrix
4. Dense clusters = recurring motifs
5. Auto-generated descriptive name based on dominant features (e.g., "Monday-crash", "Recovery-weekend")

### Mutation Classification

When an expected motif deforms, classify by impact on sleep quality (feature 16):

- **Silent** — quality difference < 0.05 (on [0,1] scale) ≈ negligible change
- **Missense** — quality difference 0.05-0.15 ≈ moderate degradation
- **Nonsense** — quality difference > 0.15 ≈ pattern broken (jet lag, illness)

### Gene Expression

Same motif under different strand 2 contexts → different outcomes. Detection: group motif instances, partition by context features, compare quality outcomes. The context feature with the largest outcome delta is the "expression regulator."

---

## 6. Health Markers

The helix geometry and pattern analysis enable detection of clinical-grade markers:

### Circadian Anarchy (ISWRD)

**Detection:** When the helix loses structural coherence — consecutive days have wildly different bedtimes with no periodic pattern.
**Metric:** `circadianCoherence = mean(cosinorR²) over 14 days`. If < 0.2, flag as circadian anarchy.
**Visual:** In 3D, the helix structure collapses — strands cross erratically.

### Fragmentation Score

**Detection:** High microawakening count from HealthKit sleep phases.
**Metric:** Count of `.awake` phase transitions per night from `SleepRecord.phases`.
**Visual:** Surface roughness on the helix strand — "dentada/rugosa".

### Phase Drift Severity

**Detection:** Consistent shift of bedtime/wake over days — the helix "leans" instead of being vertical.
**Metric:** `driftRate` from `SleepRecord.driftMinutes` trend over 7+ days.
**Visual:** Helix radius expands when misalignment is severe.

### Paradoxical Insomnia Indicator

**Detection:** Discrepancy between objective data (HealthKit sensor) and subjective report (if user logs perceived sleep quality).
**Metric:** Difference between objective duration and subjective perceived duration. When objective shows 7h but user reports "slept terribly" → flag.
**Note:** Requires future subjective logging feature. Engine computes the metric when data is available.

### Output

```swift
struct HealthMarkers {
    let circadianCoherence: Double      // [0,1], <0.2 = anarchy
    let fragmentationScore: Double      // [0,1], higher = more fragmented
    let driftSeverity: Double           // abs(minutes/day), >15 = significant
    let paradoxicalInsomnia: Double?    // discrepancy score, nil if no subjective data
    let alerts: [HealthAlert]           // triggered alerts with severity
}
```

---

## 7. Double Helix Modes

The double helix supports multiple comparison modes. V1 implements mode 1. Others are defined for future expansion.

### Mode 1: Real vs. Optimal (V1)

- **Strand 1:** Your actual sleep data
- **Strand 2:** Your optimal sleep window based on chronotype (from `ChronotypeResult` + `SleepGoal`)
- **Base pairs:** How far each night deviates from your optimal
- **Visual:** When strands align → sleeping in your window. When they diverge → misalignment.

### Mode 2: Objective vs. Subjective (Future)

- **Strand 1:** Sensor data (HealthKit)
- **Strand 2:** User-reported diary (future feature)
- Detects paradoxical insomnia

### Mode 3: Partner Sync (Future)

- **Strand 1:** Your sleep
- **Strand 2:** Partner's sleep (shared via CloudKit)
- Detects how microawakenings propagate between partners

---

## 8. Prediction by Alignment

### Algorithm

1. Encode the current week up to today as a partial sequence
2. DTW-partial against all complete weeks in history
3. Rank top-5 most similar weeks by DTW score (weighted by SleepBLOSUM)
4. Look at what happened in the remaining days of those weeks
5. Weighted average of outcomes, weights = inverse DTW distance
6. Cancellation: if new data arrives during computation, cancel via `Task` cooperative cancellation and restart

### Integration with PredictionService (after Step 0 refactoring)

```
PredictionService.generatePrediction()
  ├→ MLPredictionEngine                   → PredictionOutput
  ├→ HeuristicPredictionEngine            → PredictionOutput
  ├→ SequenceAlignmentEngine (NEW)        → PredictionOutput
  └→ Ensemble: weighted average of all 3
```

**Adaptive weights:**
- <4 weeks: alignment weight = 0 (not enough data)
- 4-8 weeks: alignment weight = 0.15
- 8+ weeks: weight grows based on rolling 14-day accuracy vs. other engines
- Cap at 0.4 — alignment enriches but doesn't dominate

### Presentation to User

**Passive:** "This week resembles Feb 15 (87% similar). You slept well after exercising Wednesday."

**Interactive (3D):** Similar weeks highlighted with cyan glow. Tap → overlay comparison.

**Predictive:** Alignment confidence indicator alongside existing prediction badge.

---

## 9. Data Contract (SleepDNAProfile)

```swift
public struct SleepDNAProfile: Sendable {
    // Encoding
    let nucleotides: [DayNucleotide]
    let sequences: [WeekSequence]

    // Phase synchrony
    let basePairs: [BasePairSynchrony]

    // Patterns
    let motifs: [SleepMotif]
    let mutations: [SleepMutation]
    let clusters: [WeekCluster]
    let expressionRules: [ExpressionRule]

    // Prediction
    let currentWeekSimilar: [WeekAlignment]
    let prediction: SequencePrediction?

    // Scoring
    let scoringMatrix: SleepBLOSUM

    // Health
    let healthMarkers: HealthMarkers

    // Geometry (for 3D renderer)
    let helixGeometry: [DayHelixParams]

    // Metadata
    let tier: AnalysisTier              // .basic, .intermediate, .full
    let computedAt: Date
    let dataWeeks: Int
}

public struct DayHelixParams: Sendable {
    let day: Int
    let twistAngle: Double              // from PLV
    let helixRadius: Double             // from midSleep deviation
    let strandThickness: Double         // from N3 proportion
    let surfaceRoughness: Double        // from fragmentation
}

public enum AnalysisTier: Sendable {
    case basic          // <4 weeks: correlations only
    case intermediate   // 4-8 weeks: short DTW
    case full           // 8+ weeks: everything
}
```

### Key Types (shape definitions)

```swift
public struct SleepMotif: Identifiable, Sendable {
    let id: UUID
    let name: String                    // auto-generated: "Monday-crash"
    let windowSize: Int                 // 3-5 days
    let centroid: [DayNucleotide]       // average pattern
    let instanceCount: Int
    let avgQuality: Double              // typical sleep quality during this motif
}

public struct SleepMutation: Identifiable, Sendable {
    let id: UUID
    let motifID: UUID                   // which motif was deformed
    let day: Int                        // when it occurred
    let classification: MutationType    // .silent, .missense, .nonsense
    let qualityDelta: Double            // actual - expected quality
    let dominantChange: Int             // which feature index changed most
}

public struct WeekCluster: Identifiable, Sendable {
    let id: UUID
    let label: String                   // auto: "Productive", "Chaotic", "Recovery"
    let centroid: WeekSequence
    let memberWeeks: [Int]              // week indices
    let avgQuality: Double
}

public struct WeekAlignment: Sendable {
    let weekIndex: Int
    let dtwScore: Double                // lower = more similar
    let similarity: Double              // normalized to [0,1]
    let alignmentPath: [(Int, Int)]     // (currentDay, historicalDay) pairs
}

public struct SequencePrediction: Sendable {
    let predictedBedtime: Double
    let predictedWake: Double
    let predictedDuration: Double
    let confidence: Double              // [0,1] based on alignment quality
    let basedOn: [WeekAlignment]        // which weeks informed this
}

public struct ExpressionRule: Identifiable, Sendable {
    let id: UUID
    let motifID: UUID
    let regulatorFeature: Int           // which strand 2 feature
    let regulatorThreshold: Double      // above/below this value
    let qualityWith: Double             // quality when regulator is active
    let qualityWithout: Double          // quality when regulator is absent
}
```

---

## 10. File Structure

```
SpiralKit/Sources/SpiralKit/
  Analysis/
    SleepDNA/
      DayNucleotide.swift            — day encoding (16 features, sin/cos, normalization)
      WeekSequence.swift             — 7-day sequence, sliding window generation
      HilbertPhaseAnalyzer.swift     — Hilbert Transform, PLV, base pair synchrony
      DTWEngine.swift                — Dynamic Time Warping with SleepBLOSUM weights
      SleepBLOSUM.swift              — adaptive diagonal weight vector, learning
      MotifDiscovery.swift           — weekly window clustering, motif naming
      MutationClassifier.swift       — silent/missense/nonsense classification
      ExpressionAnalyzer.swift       — context-dependent motif outcome analysis
      HealthMarkerDetector.swift     — circadian coherence, fragmentation, drift, alerts
      HelixGeometryComputer.swift    — twist, radius, thickness, roughness per day
      SequenceAlignmentEngine.swift  — prediction engine (conforms to PredictionEngineProtocol)
      SleepDNAProfile.swift          — all output types defined above
      SleepDNAComputer.swift         — orchestrator: runs full pipeline, caching, cancellation
```

### SwiftData Models (in app target)

```
spiral journey project/Models/
  SDSleepDNASnapshot.swift           — cached SleepDNAProfile
  SDSleepBLOSUM.swift                — persisted scoring matrix weights (16 doubles)
```

---

## 11. Performance

- **DTW weekly:** O(n²) per pair. 52 weeks = 1,326 pairs × ~1ms = ~1.3 seconds
- **Motif discovery:** Weekly windows only (52/year). Random sub-sampling for sub-weekly. Capped at 200 DTW comparisons for fine motifs.
- **Hilbert Transform:** O(n log n) FFT per feature pair per window. 8×8 = 64 pairs × 14-day window = negligible
- **Total pipeline:** <5 seconds for 1 year of data on modern iPhone
- **Background execution:** `Task.detached(priority: .utility)` with cooperative cancellation
- **Caching:** `SDSleepDNASnapshot` in SwiftData. Recalculate only when new data arrives.
- **watchOS:** Engine runs but with reduced computation (tier forced to `.basic` or `.intermediate` to conserve battery). Full analysis only on iPhone.

---

## 12. Testing Strategy

- **DayNucleotide:** Sin/cos encoding roundtrip, event-to-day mapping with period, fixed normalization caps, edge cases (no events, max events)
- **HilbertPhaseAnalyzer:** Known in-phase signals → PLV ≈ 1.0, known anti-phase → PLV ≈ 0.0, random → PLV ≈ 0.0
- **DTWEngine:** Known-distance pairs, symmetry, triangle inequality, SleepBLOSUM weight effects on ranking
- **MotifDiscovery:** Synthetic data with 3 planted motifs, verify all 3 discovered
- **MutationClassifier:** Synthetic deviations with known quality deltas, verify classification thresholds
- **HealthMarkerDetector:** Synthetic fragmented data → high fragmentation score, stable data → low
- **SequenceAlignmentEngine:** Partial-week alignment against known history, verify prediction within ±30 min
- **SleepBLOSUM:** Weight convergence: synthetic data where caffeine is 3× more important → caffeine weight should be highest after learning
- **Integration:** Full pipeline from SleepRecord → SleepDNAProfile

---

## 13. Implementation Order

```
0. Refactor PredictionService (pluggable engines + ensemble)
1. DayNucleotide + WeekSequence          (encoding layer)
2. HilbertPhaseAnalyzer                   (base pairs)
3. DTWEngine + SleepBLOSUM               (comparison layer)
4. MotifDiscovery                         (pattern detection)
5. MutationClassifier + ExpressionAnalyzer (classification)
6. HealthMarkerDetector                   (clinical markers)
7. HelixGeometryComputer                  (3D parameters)
8. SequenceAlignmentEngine               (prediction)
9. SleepDNAComputer + SleepDNAProfile    (orchestration + cancellation)
10. Integration with PredictionService    (ensemble)
11. Integration with CoachEngine/LLM      (insights)
12. SwiftData persistence                 (caching — last, so tests run without persistence)
```

Sub-projects 2 (3D Visualization with RealityKit) and 3 (Insights UI) will be specified separately after the engine is implemented.
