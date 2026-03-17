# SleepDNA Engine — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Sub-project 1 of 3 (Engine → 3D Visualization → Insights UI)

## Context

Spiral Journey models sleep as a spiral. This spec extends the model with a double-helix DNA metaphor: two interleaved strands (sleep data + activity/context) with cross-strand correlations ("base pairs"). The engine encodes daily data as "nucleotides", groups them into weekly "sequences", and uses Dynamic Time Warping (DTW) to find similar weeks, discover recurring motifs ("genes"), classify deviations ("mutations"), and predict future sleep by sequence alignment.

### Goals

- Detect invisible patterns that day-by-day or simple rolling-average analysis misses (hidden cycles, delayed triggers, week-type clusters, predictive transitions)
- Provide a third prediction engine alongside ML (NN/GB) and heuristic
- Work from day 1 with graceful tier degradation (<4 weeks → 4-8 → 8+)
- Produce a unique, publishable scoring matrix (SleepBLOSUM) personalized per user
- Feed insights into the AI coach and future 3D visualization

### Constraints

- Module lives in SpiralKit (shared by iOS and Watch)
- Reads from existing data types (SleepRecord, CircadianEvent, CosinorResult, TwoProcessModel)
- Does NOT modify existing prediction pipeline — registers as an additional engine
- DTW computation runs on background thread, cached, recalculated only on new data
- Privacy: all computation on-device, no cloud

---

## 1. Nucleotide Encoding

Each day is encoded as a normalized vector of 12 features — a "nucleotide".

### Strand 1 — Sleep (intrinsic, features 1-6)

| # | Feature | Source | Normalization |
|---|---------|--------|---------------|
| 1 | bedtimeHour | SleepRecord.bedtimeHour | circular → [0,1] via sin/cos or /24 |
| 2 | wakeupHour | SleepRecord.wakeupHour | circular → [0,1] |
| 3 | sleepDuration | SleepRecord.sleepDuration | /12h → [0,1] |
| 4 | processS | TwoProcessModel.computeContinuous() | already [0,1] |
| 5 | cosinorAcrophase | CosinorResult.acrophase | circular → [0,1] |
| 6 | cosinorR² | CosinorResult.r2 | already [0,1] |

### Strand 2 — Context (extrinsic, features 7-12)

| # | Feature | Source | Normalization |
|---|---------|--------|---------------|
| 7 | caffeine | CircadianEvent count (type: .caffeine) | /max → [0,1] |
| 8 | exercise | CircadianEvent count (type: .exercise) | 0 or 1 |
| 9 | alcohol | CircadianEvent count (type: .alcohol) | /max → [0,1] |
| 10 | stress | CircadianEvent count (type: .stress) | /max → [0,1] |
| 11 | isWeekend | SleepRecord.isWeekend | 0 or 1 |
| 12 | driftMinutes | SleepRecord.driftMinutes | /120 → [-1,1] |

### Base Pairs

Cross-strand correlations computed per day: correlation between strand 1 features and strand 2 features of the same day (e.g., caffeine ↔ bedtime delay). Stored as part of the nucleotide for use in scoring.

### Sequence

A `WeekSequence` = 7 consecutive `DayNucleotide` values = matrix 7×12. Sequences overlap by 6 days (sliding window) for dense coverage.

---

## 2. Sequence Alignment (DTW)

### Algorithm

Dynamic Time Warping between two `WeekSequence` matrices. DTW finds the optimal alignment allowing temporal warping (a Monday pattern can match a Tuesday in another week).

**Distance function:** weighted Euclidean between two nucleotides, using the SleepBLOSUM scoring matrix as weights.

**Output:** DTW distance (lower = more similar) and the alignment path (which days matched).

### SleepBLOSUM — Adaptive Scoring Matrix

A 12×12 diagonal weight matrix that personalizes DTW:

- **Initial:** equal weights (1.0) for all 12 features
- **Learned:** after 8+ weeks, compute mutual information between each feature and next-day sleep quality. Features with higher predictive power get higher weight.
- **Updated:** weekly, alongside ML model retraining cycle (same cooldown)
- **Stored:** as a flat array of 12 doubles in SwiftData (`SDSleepBLOSUM`)

This makes DTW personalized — two users with the same raw data can have different similarity scores because their sensitivities differ. This is the publishable differentiator.

### Tier Degradation

| Data available | Method | Capabilities |
|---|---|---|
| <4 weeks | Day-to-day correlation between strands | Base pairs only: "caffeine → bedtime +30min for you" |
| 4-8 weeks | DTW on short windows (3-5 days) | Micro-patterns: "post-weekend you always sleep worse" |
| 8+ weeks | Full DTW + clustering + motif discovery | Cycles, clusters, transitions, prediction by alignment |

---

## 3. Pattern Detection

### Motif Discovery ("Genes")

1. Extract all sliding windows of 3-5 days from history
2. Compute pairwise DTW distances between windows
3. Agglomerative clustering on the distance matrix
4. Dense clusters = recurring motifs
5. Each motif gets auto-generated descriptive name based on dominant features (e.g., "Monday-crash", "Recovery-weekend", "Productive-sprint")

Motifs answer: **"What are the building blocks of your sleep life?"**

### Mutation Classification

When an expected motif deforms:

- **Silent** — deviation does not affect sleep outcome (e.g., switched morning to evening exercise, same result)
- **Missense** — deviation moderately changes outcome (e.g., extra drink delays bedtime 20 min)
- **Nonsense** — deviation breaks the pattern completely (e.g., jet lag, illness)

Classification: compare the outcome (next-day sleep quality) of the deformed instance vs. the motif's typical outcome. Threshold-based: <15 min difference = silent, 15-45 min = missense, >45 min = nonsense.

### Gene Expression

Same motif can have different outcomes depending on context (strand 2):

- "Monday-crash WITH prior exercise → duration drops only 15 min"
- "Monday-crash WITHOUT exercise → drops 45 min"

Detection: group instances of the same motif, split by strand 2 feature values, compare outcomes. The strand 2 feature that most changes the outcome is the "expression regulator" for that motif.

---

## 4. Prediction by Alignment

### Algorithm

1. Encode the current week up to today as a partial sequence
2. DTW-partial against all complete weeks in history
3. Rank top-5 most similar weeks by DTW score (weighted by SleepBLOSUM)
4. Look at what happened in the remaining days of those weeks
5. Weighted average of outcomes, weights = inverse DTW distance

### Integration with PredictionService

```
PredictionService.generatePrediction()
  ├→ MLPredictionEngine (NN/GB)           → PredictionOutput
  ├→ HeuristicPredictionEngine            → PredictionOutput
  ├→ SequenceAlignmentEngine (NEW)        → PredictionOutput
  └→ Ensemble: weighted average of all 3
```

**Adaptive weights:**
- <4 weeks: alignment weight = 0 (not enough data)
- 4-8 weeks: alignment weight = 0.15
- 8+ weeks: weight grows based on rolling accuracy vs. other engines
- If alignment outperforms ML on recent 14-day accuracy, its weight increases automatically

### Presentation to User

**Passive (automatic insight):**
> "This week resembles the week of Feb 15 (87% similar). That time you slept well Thursday and Friday after exercising Wednesday."

**Interactive (exploration in 3D view):**
- Similar weeks highlighted on the helix with cyan glow
- Tap a week → overlay comparison with current
- Temporal slider to navigate alignment history

**Predictive (integrated):**
- Existing prediction badge shows predicted bedtime
- New: "alignment confidence" indicator — how much the current week resembles known patterns
- If no similar weeks: "Novel week — no precedent in your history"

---

## 5. 3D Visualization (RealityKit)

**Separate sub-project** — this spec defines the data contract the engine must provide. The 3D view spec will be written separately.

### Data Contract for 3D View

```swift
SleepDNAProfile {
    nucleotides: [DayNucleotide]       // full encoded history
    sequences: [WeekSequence]           // weekly sequences
    motifs: [SleepMotif]                // discovered recurring patterns
    mutations: [SleepMutation]          // deviations with classification
    clusters: [WeekCluster]             // week-type clusters
    currentWeekSimilar: [WeekAlignment] // top-5 similar weeks to current
    predictions: SequencePrediction     // alignment-based prediction
    scoringMatrix: SleepBLOSUM          // personalized weights
    basePairs: [BasePairCorrelation]    // cross-strand correlations
}
```

The 3D view reads this profile and renders:
- Vertical double helix (strand 1 purple, strand 2 orange)
- Nucleotide spheres colored by feature intensity
- Base pair connectors between strands
- Current week highlighted green
- Similar weeks highlighted cyan with DTW score
- Motif regions as semitransparent envelopes
- Mutations as visible deformations

---

## 6. File Structure

```
SpiralKit/Sources/SpiralKit/
  Analysis/
    SleepDNA/
      DayNucleotide.swift            — day encoding (12 features, normalization)
      WeekSequence.swift             — 7-day sequence, sliding window generation
      DTWEngine.swift                — Dynamic Time Warping with SleepBLOSUM weights
      SleepBLOSUM.swift              — adaptive scoring matrix, learning, persistence
      MotifDiscovery.swift           — sliding window clustering, motif naming
      MutationClassifier.swift       — silent/missense/nonsense classification
      ExpressionAnalyzer.swift       — context-dependent motif outcome analysis
      SequenceAlignmentEngine.swift  — prediction engine (conforms to existing protocol)
      SleepDNAProfile.swift          — consolidated output struct
      SleepDNAComputer.swift         — orchestrator: runs full pipeline, caching
```

### SwiftData Models (in app target)

```
spiral journey project/Models/
  SDSleepDNASnapshot.swift           — cached SleepDNAProfile per computation
  SDSleepBLOSUM.swift                — persisted scoring matrix weights
```

### Integration Points

| Existing component | Connection |
|---|---|
| `SleepRecord` | Input for DayNucleotide (bedtime, wake, duration, isWeekend, drift) |
| `TwoProcessModel.computeContinuous()` | Feature processS in nucleotide |
| `CosinorResult` | Features acrophase and R² in nucleotide |
| `CircadianEvent` / `SDCircadianEvent` | Strand 2 features (caffeine, exercise, etc.) |
| `PredictionService` | Registers SequenceAlignmentEngine as additional provider |
| `LLMContextBuilder` | Injects DNA insights into coach system prompt |
| `CoachEngine` | Motifs and mutations feed contextual insights |

---

## 7. Performance

- DTW is O(n²) per pair. 52 weeks = 1,326 pairs. At ~1ms/pair ≈ 1.3 seconds.
- Runs on background thread via `Task.detached(priority: .utility)`
- Cached in SwiftData (`SDSleepDNASnapshot`), recalculated only when new data arrives
- Motif discovery (agglomerative clustering) is O(n³) but on small n (windows, not raw days). With 365 days and window size 5 = ~360 windows. Manageable.
- SleepBLOSUM update: O(n × 12) mutual information computation. Negligible.

---

## 8. Testing Strategy

- **DayNucleotide:** Unit tests for normalization (circular hours, event counts, edge cases)
- **DTWEngine:** Known-distance pairs, symmetry, triangle inequality, SleepBLOSUM weight effects
- **MotifDiscovery:** Synthetic data with planted motifs, verify detection
- **MutationClassifier:** Synthetic deviations with known outcomes, verify classification
- **SequenceAlignmentEngine:** Partial-week alignment against known history, verify prediction accuracy
- **SleepBLOSUM:** Weight convergence with synthetic correlated data
- **Integration:** Full pipeline from SleepRecord → SleepDNAProfile with real-ish data

---

## Implementation Order

```
1. DayNucleotide + WeekSequence        (encoding layer)
2. DTWEngine + SleepBLOSUM             (comparison layer)
3. MotifDiscovery                       (pattern detection)
4. MutationClassifier + ExpressionAnalyzer (classification)
5. SequenceAlignmentEngine              (prediction)
6. SleepDNAComputer + SleepDNAProfile   (orchestration)
7. Integration with PredictionService   (prediction pipeline)
8. Integration with CoachEngine/LLM     (insights)
9. SwiftData persistence               (caching)
```

Sub-projects 2 (3D Visualization) and 3 (Insights UI) will be specified separately after the engine is implemented.
