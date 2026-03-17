# SleepDNA Engine — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a DNA-inspired sleep pattern analysis engine using DTW sequence alignment, Hilbert phase synchrony, motif discovery, health markers, and prediction by alignment — integrated into the existing prediction pipeline and coach.

**Architecture:** New `SleepDNA/` module in SpiralKit with 12 focused files. Reads existing types (SleepRecord, CircadianEvent, CosinorResult). Plugs into PredictionService via a new protocol. All computation on background threads with caching in SwiftData.

**Tech Stack:** Swift 6, SpiralKit (SPM package), Swift Testing, SwiftData, Accelerate (vDSP for Hilbert/FFT)

**Spec:** `docs/superpowers/specs/2026-03-17-sleep-dna-engine-design.md`

---

## File Structure

### New Files in SpiralKit

```
SpiralKit/Sources/SpiralKit/
  Analysis/
    SleepDNA/
      DayNucleotide.swift            — 16-feature day encoding with sin/cos
      WeekSequence.swift             — 7-day sliding window sequences
      HilbertPhaseAnalyzer.swift     — Hilbert Transform, PLV base pairs
      DTWEngine.swift                — Dynamic Time Warping
      SleepBLOSUM.swift              — adaptive 16-weight scoring vector
      MotifDiscovery.swift           — weekly window clustering
      MutationClassifier.swift       — silent/missense/nonsense + expression rules
      HealthMarkerDetector.swift     — circadian coherence, fragmentation, drift
      HelixGeometryComputer.swift    — twist, radius, thickness, roughness
      SequenceAlignmentEngine.swift  — partial-week DTW prediction
      SleepDNAProfile.swift          — all output types
      SleepDNAComputer.swift         — orchestrator with caching + cancellation
  Models/
    PredictionModels.swift           — ADD .sequenceAlignment to PredictionEngine enum

SpiralKit/Tests/SpiralKitTests/
  SleepDNA/
    DayNucleotideTests.swift
    WeekSequenceTests.swift
    HilbertPhaseTests.swift
    DTWEngineTests.swift
    SleepBLOSUMTests.swift
    MotifDiscoveryTests.swift
    MutationClassifierTests.swift
    HealthMarkerTests.swift
    SequenceAlignmentTests.swift
    SleepDNAComputerTests.swift
```

### Modified Files in App Target

```
spiral journey project/
  Services/
    PredictionService.swift          — pluggable engine protocol + ensemble
    SpiralStore.swift                — sleepDNAPredictionEnabled flag
    LLMContextBuilder.swift          — DNA insights in coach prompt
  Models/
    SDSleepDNASnapshot.swift         — cached profile (NEW)
    SDSleepBLOSUM.swift              — persisted weights (NEW)
```

---

## Key Existing APIs (Reference)

```swift
// SleepRecord — fields used for nucleotide encoding
public struct SleepRecord {
    var day: Int, date: Date, isWeekend: Bool
    var bedtimeHour: Double, wakeupHour: Double, sleepDuration: Double
    var phases: [PhaseInterval]         // .phase is SleepPhase: .deep/.rem/.light/.awake
    var hourlyActivity: [HourlyActivity] // .hour: Int, .activity: Double 0-1
    var cosinor: CosinorResult          // .acrophase, .r2, .mesor, .amplitude
    var driftMinutes: Double
}

// CircadianEvent — event types for strand 2
public enum EventType: String, Codable, CaseIterable, Sendable {
    case light, exercise, melatonin, caffeine, screenLight, alcohol, meal, stress
}
public struct CircadianEvent {
    var type: EventType, absoluteHour: Double, timestamp: Date
}

// PredictionEngine — currently 2 cases, will add .sequenceAlignment
public enum PredictionEngine: String, Codable, Sendable {
    case heuristic, ml
}

// PredictionOutput — what engines produce
public struct PredictionOutput {
    init(predictedBedtimeHour:, predictedWakeHour:, predictedDuration:,
         confidence: PredictionConfidence, engine: PredictionEngine,
         generatedAt: Date, targetDate: Date)
}

// Test pattern — Swift Testing, @Suite/@Test/#expect, makeRecord helper
// CosinorResult.empty is available for tests
```

---

## Chunk 1: Foundation Layer (Tasks 0-2)

### Task 0: PredictionService Refactoring

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Models/PredictionModels.swift`
- Modify: `spiral journey project/Services/PredictionService.swift`
- Modify: `spiral journey project/Services/SpiralStore.swift`

This is a prerequisite. The current PredictionService is a hardcoded if/else. We need a protocol for pluggable engines.

- [ ] **Step 1: Add `.sequenceAlignment` to PredictionEngine enum**

In `PredictionModels.swift`, add the new case:
```swift
public enum PredictionEngine: String, Codable, Sendable {
    case heuristic
    case ml
    case sequenceAlignment
}
```

- [ ] **Step 2: Add `sleepDNAPredictionEnabled` flag to SpiralStore**

In `SpiralStore.swift`, near `mlPredictionEnabled` (~line 188), add:
```swift
var sleepDNAPredictionEnabled: Bool = false { didSet { save() } }
```

Also add it to the `Stored` struct and `save()`/`load()` methods.

- [ ] **Step 3: Prepare PredictionService for third engine**

In `PredictionService.swift`, modify `generatePrediction()` to support a third engine branch. For now, add a placeholder:
```swift
// After existing ML/heuristic block:
// TODO: SequenceAlignmentEngine integration (Task 10)
// if store.sleepDNAPredictionEnabled { ... }
```

The full ensemble logic will be wired in Task 12.

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: prepare PredictionService for pluggable engines

Add .sequenceAlignment case to PredictionEngine enum.
Add sleepDNAPredictionEnabled flag to SpiralStore.
Placeholder for SequenceAlignmentEngine integration."
```

---

### Task 1: DayNucleotide

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/DayNucleotide.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/DayNucleotideTests.swift`

The core encoding unit — each day becomes a 16-element vector.

- [ ] **Step 1: Write tests**

```swift
import Testing
@testable import SpiralKit

@Suite("DayNucleotide")
struct DayNucleotideTests {

    @Test("Encodes 16 features from a SleepRecord")
    func encodesCorrectFeatureCount() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide(from: record, events: [], period: 24, goalDuration: 8)
        #expect(nuc.features.count == 16)
    }

    @Test("Sin/cos bedtime encoding for 23:00")
    func sinCosBedtime() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide(from: record, events: [], period: 24, goalDuration: 8)
        let expected_sin = sin(2 * .pi * 23.0 / 24.0)
        let expected_cos = cos(2 * .pi * 23.0 / 24.0)
        #expect(abs(nuc.features[0] - expected_sin) < 0.001)
        #expect(abs(nuc.features[1] - expected_cos) < 0.001)
    }

    @Test("Caffeine count capped at 5")
    func caffeineCap() {
        let events = (0..<8).map { _ in
            CircadianEvent(type: .caffeine, absoluteHour: 0.5)
        }
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide(from: record, events: events, period: 24, goalDuration: 8)
        #expect(nuc.features[8] == 1.0) // capped at 5/5 = 1.0
    }

    @Test("Sleep quality composite is [0,1]")
    func qualityRange() {
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide(from: record, events: [], period: 24, goalDuration: 8)
        #expect(nuc.features[15] >= 0 && nuc.features[15] <= 1)
    }

    @Test("Events mapped by absoluteHour range")
    func eventDayMapping() {
        let events = [
            CircadianEvent(type: .caffeine, absoluteHour: 10),  // day 0
            CircadianEvent(type: .caffeine, absoluteHour: 35),  // day 1
        ]
        let record = makeRecord(day: 0, bedtime: 23, wakeup: 7, duration: 8)
        let nuc = DayNucleotide(from: record, events: events, period: 24, goalDuration: 8)
        // Only day 0 caffeine should count (absoluteHour 0-24)
        #expect(nuc.features[8] == 1.0 / 5.0) // 1 caffeine / 5 max
    }

    // Helper — same pattern as TwoProcessTests
    private func makeRecord(day: Int, bedtime: Double, wakeup: Double, duration: Double) -> SleepRecord {
        SleepRecord(
            day: day, date: Date(), isWeekend: day % 7 >= 5,
            bedtimeHour: bedtime, wakeupHour: wakeup, sleepDuration: duration,
            phases: [], hourlyActivity: (0..<24).map { h in
                let asleep = (bedtime > wakeup)
                    ? (Double(h) >= bedtime || Double(h) < wakeup)
                    : (Double(h) >= bedtime && Double(h) < wakeup)
                return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
            },
            cosinor: .empty
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SpiralKit && swift test --filter DayNucleotide 2>&1 | tail -20`

- [ ] **Step 3: Implement DayNucleotide**

```swift
// SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/DayNucleotide.swift
import Foundation

public struct DayNucleotide: Codable, Sendable {
    /// 16-element feature vector: [sinBed, cosBed, sinWake, cosWake, duration,
    /// processS, acrophase, cosinorR2, caffeine, exercise, alcohol, melatonin,
    /// stress, isWeekend, drift, sleepQuality]
    public let day: Int
    public let date: Date
    public let features: [Double]  // count == 16

    /// Strand 1 (sleep): features[0..<8]
    public var strand1: ArraySlice<Double> { features[0..<8] }
    /// Strand 2 (context): features[8..<16]
    public var strand2: ArraySlice<Double> { features[8..<16] }

    // Fixed normalization caps
    static let caffeineCap = 5.0
    static let alcoholCap = 3.0
    static let stressCap = 3.0
    static let driftCap = 120.0

    public init(
        from record: SleepRecord,
        events: [CircadianEvent],
        period: Double = 24,
        goalDuration: Double = 8,
        processS: Double? = nil
    ) {
        self.day = record.day
        self.date = record.date

        // Event-to-day mapping (same as PredictionFeatureBuilder)
        let dayStart = Double(record.day) * period
        let dayEnd = dayStart + period
        let dayEvents = events.filter { $0.absoluteHour >= dayStart && $0.absoluteHour < dayEnd }

        let caffeine = Double(dayEvents.filter { $0.type == .caffeine }.count)
        let exercise = Double(dayEvents.filter { $0.type == .exercise }.count)
        let alcohol = Double(dayEvents.filter { $0.type == .alcohol }.count)
        let melatonin = Double(dayEvents.filter { $0.type == .melatonin }.count)
        let stress = Double(dayEvents.filter { $0.type == .stress }.count)

        // Strand 1: Sleep (8 values)
        let sinBed = sin(2 * .pi * record.bedtimeHour / 24.0)
        let cosBed = cos(2 * .pi * record.bedtimeHour / 24.0)
        let sinWake = sin(2 * .pi * record.wakeupHour / 24.0)
        let cosWake = cos(2 * .pi * record.wakeupHour / 24.0)
        let duration = min(record.sleepDuration / 12.0, 1.0)
        let pS = processS ?? 0.5
        let acrophase = record.cosinor.acrophase / 24.0
        let cosinorR2 = record.cosinor.r2

        // Strand 2: Context (8 values)
        let caffeineNorm = min(caffeine / Self.caffeineCap, 1.0)
        let exerciseNorm = min(exercise, 1.0)
        let alcoholNorm = min(alcohol / Self.alcoholCap, 1.0)
        let melatoninNorm = min(melatonin, 1.0)
        let stressNorm = min(stress / Self.stressCap, 1.0)
        let isWeekend = record.isWeekend ? 1.0 : 0.0
        let drift = max(-1, min(1, record.driftMinutes / Self.driftCap))

        // Sleep quality composite
        let durationScore = min(record.sleepDuration / goalDuration, 1.0)
        let quality = durationScore * cosinorR2 // simplified; SRI not available per-day

        self.features = [
            sinBed, cosBed, sinWake, cosWake, duration, pS, acrophase, cosinorR2,
            caffeineNorm, exerciseNorm, alcoholNorm, melatoninNorm, stressNorm,
            isWeekend, drift, quality
        ]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Build iOS project**
- [ ] **Step 6: Commit**

---

### Task 2: WeekSequence

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/WeekSequence.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/WeekSequenceTests.swift`

- [ ] **Step 1: Write tests**

Test: 7 nucleotides → 1 sequence. 14 nucleotides → 8 sequences (overlapping by 6). Empty input → empty.

- [ ] **Step 2: Implement WeekSequence**

```swift
public struct WeekSequence: Codable, Sendable {
    public let startDay: Int
    public let nucleotides: [DayNucleotide]  // exactly 7

    /// Feature matrix 7×16
    public var matrix: [[Double]] { nucleotides.map(\.features) }

    /// Generate overlapping weekly sequences from nucleotides
    public static func generateSequences(from nucleotides: [DayNucleotide]) -> [WeekSequence] {
        guard nucleotides.count >= 7 else { return [] }
        let sorted = nucleotides.sorted { $0.day < $1.day }
        return (0...(sorted.count - 7)).map { i in
            WeekSequence(startDay: sorted[i].day, nucleotides: Array(sorted[i..<(i+7)]))
        }
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

## Chunk 2: Analysis Layer (Tasks 3-5)

### Task 3: HilbertPhaseAnalyzer

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HilbertPhaseAnalyzer.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/HilbertPhaseTests.swift`

Uses Accelerate (vDSP) for FFT-based Hilbert Transform.

- [ ] **Step 1: Write tests**

Test: two identical sine waves → PLV ≈ 1.0. Two random signals → PLV ≈ 0.0. Anti-phase → PLV ≈ 1.0 with π phase diff.

- [ ] **Step 2: Implement**

```swift
import Accelerate

public struct BasePairSynchrony: Codable, Sendable {
    public let sleepFeatureIndex: Int
    public let contextFeatureIndex: Int
    public let plv: Double              // [0,1]
    public let meanPhaseDiff: Double    // radians
    public let lagDays: Int             // detected lag
}

public enum HilbertPhaseAnalyzer {
    /// Compute PLV between all strand1 × strand2 feature pairs over a window
    public static func analyze(
        nucleotides: [DayNucleotide],
        windowSize: Int = 14
    ) -> [BasePairSynchrony] {
        guard nucleotides.count >= windowSize else { return [] }
        let recent = Array(nucleotides.suffix(windowSize))
        var results: [BasePairSynchrony] = []

        // 8 strand1 features × 8 strand2 features = 64 pairs
        for s1 in 0..<8 {
            for s2 in 8..<16 {
                let signal1 = recent.map { $0.features[s1] }
                let signal2 = recent.map { $0.features[s2] }
                let (plv, meanPhase) = computePLV(signal1, signal2)
                if plv > 0.3 { // only report meaningful synchrony
                    results.append(BasePairSynchrony(
                        sleepFeatureIndex: s1, contextFeatureIndex: s2,
                        plv: plv, meanPhaseDiff: meanPhase, lagDays: 0
                    ))
                }
            }
        }
        return results.sorted { $0.plv > $1.plv }
    }

    /// Hilbert Transform via FFT → analytic signal → instantaneous phase
    static func computePLV(_ a: [Double], _ b: [Double]) -> (plv: Double, meanPhase: Double) {
        guard a.count == b.count, a.count >= 4 else { return (0, 0) }
        let phaseA = instantaneousPhase(a)
        let phaseB = instantaneousPhase(b)

        // PLV = |mean(exp(i·Δθ))|
        var sumReal = 0.0, sumImag = 0.0
        for i in 0..<phaseA.count {
            let diff = phaseA[i] - phaseB[i]
            sumReal += cos(diff)
            sumImag += sin(diff)
        }
        let n = Double(phaseA.count)
        let plv = sqrt(sumReal * sumReal + sumImag * sumImag) / n
        let meanPhase = atan2(sumImag / n, sumReal / n)
        return (plv, meanPhase)
    }

    /// Hilbert Transform using Accelerate vDSP FFT
    static func instantaneousPhase(_ signal: [Double]) -> [Double] {
        // Implementation uses vDSP.FFT → zero negative frequencies → inverse FFT
        // → atan2(imag, real) for instantaneous phase
        // ... (use Accelerate framework)
    }
}
```

**Note:** The exact Accelerate/vDSP FFT implementation for the Hilbert Transform should follow Apple's documentation. The key steps are: FFT → zero out negative frequencies → double positive frequencies → inverse FFT → the imaginary part is the Hilbert transform → `atan2(hilbert, original)` gives instantaneous phase.

- [ ] **Step 3: Run tests, build, commit**

---

### Task 4: DTWEngine

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/DTWEngine.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/DTWEngineTests.swift`

- [ ] **Step 1: Write tests**

Test: identical sequences → distance 0. Reversed sequences → high distance. Symmetry: dtw(a,b) == dtw(b,a). Triangle inequality.

- [ ] **Step 2: Implement DTW**

```swift
public enum DTWEngine {
    /// DTW distance between two WeekSequences using weighted Euclidean
    public static func distance(
        _ a: WeekSequence,
        _ b: WeekSequence,
        weights: [Double]? = nil  // SleepBLOSUM weights (16 elements)
    ) -> (distance: Double, path: [(Int, Int)]) {
        let n = a.nucleotides.count  // 7
        let m = b.nucleotides.count  // 7
        let w = weights ?? Array(repeating: 1.0, count: 16)

        // Cost matrix
        var cost = Array(repeating: Array(repeating: Double.infinity, count: m), count: n)
        cost[0][0] = weightedDistance(a.nucleotides[0].features, b.nucleotides[0].features, w)

        for i in 1..<n { cost[i][0] = cost[i-1][0] + weightedDistance(a.nucleotides[i].features, b.nucleotides[0].features, w) }
        for j in 1..<m { cost[0][j] = cost[0][j-1] + weightedDistance(a.nucleotides[0].features, b.nucleotides[j].features, w) }

        for i in 1..<n {
            for j in 1..<m {
                let d = weightedDistance(a.nucleotides[i].features, b.nucleotides[j].features, w)
                cost[i][j] = d + min(cost[i-1][j], cost[i][j-1], cost[i-1][j-1])
            }
        }

        // Backtrack for alignment path
        let path = backtrack(cost)
        return (cost[n-1][m-1], path)
    }

    /// Partial DTW — compare partial sequence (current week) against full weeks
    public static func partialDistance(
        partial: [DayNucleotide],
        full: WeekSequence,
        weights: [Double]? = nil
    ) -> (distance: Double, path: [(Int, Int)]) {
        // Same as DTW but only uses partial.count rows
        // ... implementation
    }

    static func weightedDistance(_ a: [Double], _ b: [Double], _ w: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<min(a.count, b.count) {
            let diff = a[i] - b[i]
            sum += w[i] * diff * diff
        }
        return sqrt(sum)
    }

    static func backtrack(_ cost: [[Double]]) -> [(Int, Int)] {
        // Standard DTW backtracking from bottom-right to top-left
        // ... implementation
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

### Task 5: SleepBLOSUM

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SleepBLOSUM.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/SleepBLOSUMTests.swift`

- [ ] **Step 1: Write tests**

Test: initial weights all 1.0. After learning with synthetic data where caffeine has 3× impact, caffeine weight should be highest. Weights always positive.

- [ ] **Step 2: Implement**

```swift
public struct SleepBLOSUM: Codable, Sendable {
    /// Diagonal weight vector (16 elements). Higher = more important in DTW.
    public var weights: [Double]  // count == 16

    public static let initial = SleepBLOSUM(weights: Array(repeating: 1.0, count: 16))

    /// Learn weights from history by computing mutual information
    /// between each feature and next-day sleep quality (feature[15]).
    public static func learn(from nucleotides: [DayNucleotide]) -> SleepBLOSUM {
        guard nucleotides.count >= 14 else { return .initial }
        var weights = Array(repeating: 1.0, count: 16)

        for f in 0..<16 {
            let series = nucleotides.map { $0.features[f] }
            let quality = nucleotides.dropFirst().map { $0.features[15] }
            let mi = mutualInformation(Array(series.dropLast()), Array(quality))
            weights[f] = max(0.1, mi * 10)  // scale MI to usable range, min 0.1
        }

        // Normalize so max = 3.0 (prevents any single feature from dominating)
        let maxW = weights.max() ?? 1.0
        if maxW > 0 { weights = weights.map { $0 / maxW * 3.0 } }

        return SleepBLOSUM(weights: weights)
    }

    /// Simplified mutual information via binned histogram
    static func mutualInformation(_ x: [Double], _ y: [Double]) -> Double {
        // Bin both signals into 5 bins, compute joint and marginal entropy
        // MI = H(X) + H(Y) - H(X,Y)
        // ... implementation
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

## Chunk 3: Pattern Detection (Tasks 6-9)

### Task 6: MotifDiscovery

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/MotifDiscovery.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/MotifDiscoveryTests.swift`

- [ ] **Step 1: Write tests**

Test: synthetic data with 3 repeated patterns → 3 motifs discovered. Each motif has instanceCount >= 2. Names auto-generated.

- [ ] **Step 2: Implement**

```swift
public struct SleepMotif: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let windowSize: Int
    public let centroid: [DayNucleotide]
    public let instanceCount: Int
    public let instanceDays: [[Int]]     // day indices per instance
    public let avgQuality: Double
}

public enum MotifDiscovery {
    /// Discover motifs from weekly sequences via agglomerative clustering
    public static func discover(
        sequences: [WeekSequence],
        weights: [Double]? = nil,
        maxMotifs: Int = 10
    ) -> [SleepMotif] {
        guard sequences.count >= 4 else { return [] }

        // 1. Pairwise DTW distance matrix (cap at 200 comparisons via sampling)
        let pairs = min(sequences.count, 200)
        let sampled = sequences.count > 200
            ? Array(sequences.shuffled().prefix(200))
            : sequences

        // 2. Agglomerative clustering (single-linkage, cut at threshold)
        // 3. Extract clusters with >= 2 members as motifs
        // 4. Auto-name each motif based on dominant features
        // ... implementation
    }

    /// Auto-generate motif name from dominant features
    static func nameMotif(_ centroid: [DayNucleotide]) -> String {
        // Look at which features deviate most from mean
        // Map to human-readable: "Late-night", "Recovery", "Caffeine-heavy", etc.
        // ... implementation
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

### Task 7: MutationClassifier + ExpressionAnalyzer

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/MutationClassifier.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/MutationClassifierTests.swift`

- [ ] **Step 1: Write tests**

Test: quality delta < 0.05 → silent. Delta 0.05-0.15 → missense. Delta > 0.15 → nonsense. Expression rule: exercise reduces quality drop of a motif.

- [ ] **Step 2: Implement**

```swift
public enum MutationType: String, Codable, Sendable {
    case silent     // quality delta < 0.05
    case missense   // 0.05 - 0.15
    case nonsense   // > 0.15
}

public struct SleepMutation: Identifiable, Codable, Sendable {
    public let id: UUID
    public let motifID: UUID
    public let day: Int
    public let classification: MutationType
    public let qualityDelta: Double
    public let dominantChangeIndex: Int
}

public struct ExpressionRule: Identifiable, Codable, Sendable {
    public let id: UUID
    public let motifID: UUID
    public let regulatorFeatureIndex: Int   // strand 2 feature
    public let regulatorThreshold: Double
    public let qualityWith: Double
    public let qualityWithout: Double
}

public enum MutationClassifier {
    public static func classify(
        nucleotides: [DayNucleotide],
        motifs: [SleepMotif],
        weights: [Double]? = nil
    ) -> (mutations: [SleepMutation], rules: [ExpressionRule]) {
        // For each day, find closest motif, compute quality delta, classify
        // For expression: group motif instances by strand 2 features, compare outcomes
        // ... implementation
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

### Task 8: HealthMarkerDetector

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HealthMarkerDetector.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/HealthMarkerTests.swift`

- [ ] **Step 1: Write tests**

Test: stable cosinorR² over 14 days → high coherence. Random bedtimes → low coherence. Many awake phases → high fragmentation.

- [ ] **Step 2: Implement**

```swift
public struct HealthMarkers: Codable, Sendable {
    public let circadianCoherence: Double   // mean cosinorR² over 14 days, <0.2 = anarchy
    public let fragmentationScore: Double   // awake phase transitions per night, normalized
    public let driftSeverity: Double        // abs(mean drift), >15min/day = significant
    public let alerts: [HealthAlert]
}

public struct HealthAlert: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: AlertType
    public let severity: AlertSeverity
    public let message: String
}

public enum AlertType: String, Codable, Sendable {
    case circadianAnarchy, highFragmentation, severeDrift, novelPattern
}

public enum AlertSeverity: String, Codable, Sendable {
    case info, warning, urgent
}

public enum HealthMarkerDetector {
    public static func analyze(records: [SleepRecord]) -> HealthMarkers {
        let recent = Array(records.suffix(14))
        // Coherence: mean of cosinorR² values
        // Fragmentation: count .awake phases per night, normalize
        // Drift: mean of driftMinutes, flag if >15
        // Generate alerts based on thresholds
        // ... implementation
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

### Task 9: HelixGeometryComputer

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HelixGeometryComputer.swift`

No tests needed for v1 — pure geometric mapping. Tests would require visual validation.

- [ ] **Step 1: Implement**

```swift
public struct DayHelixParams: Codable, Sendable {
    public let day: Int
    public let twistAngle: Double       // PLV → twist between strands
    public let helixRadius: Double      // midSleep deviation from chronotype
    public let strandThickness: Double  // N3 (deep sleep) proportion
    public let surfaceRoughness: Double // fragmentation (awake count)
}

public enum HelixGeometryComputer {
    public static func compute(
        records: [SleepRecord],
        basePairs: [BasePairSynchrony],
        chronotype: ChronotypeResult?,
        maxTwist: Double = .pi / 3     // max 60° twist
    ) -> [DayHelixParams] {
        records.map { record in
            // Twist: average PLV of base pairs for this day's window
            let avgPLV = basePairs.isEmpty ? 0.5 : basePairs.map(\.plv).reduce(0, +) / Double(basePairs.count)
            let twist = avgPLV * maxTwist

            // Radius: midSleep deviation from chronotype ideal
            let midSleep = (record.bedtimeHour + record.wakeupHour) / 2
            let idealMid = chronotype?.chronotype.idealBedRange.0 ?? 23.5
            let deviation = abs(circularTimeDiff(midSleep, idealMid))
            let radius = min(deviation / 3.0, 1.0)  // normalize, cap at 3h deviation

            // Thickness: deep sleep proportion
            let n3Count = record.phases.filter { $0.phase == .deep }.count
            let totalPhases = max(record.phases.count, 1)
            let thickness = Double(n3Count) / Double(totalPhases)

            // Roughness: awake transitions
            let awakeCount = record.phases.filter { $0.phase == .awake }.count
            let roughness = min(Double(awakeCount) / 10.0, 1.0)

            return DayHelixParams(
                day: record.day, twistAngle: twist,
                helixRadius: radius, strandThickness: thickness,
                surfaceRoughness: roughness
            )
        }
    }
}
```

- [ ] **Step 2: Build and commit**

---

## Chunk 4: Prediction & Orchestration (Tasks 10-12)

### Task 10: SequenceAlignmentEngine

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SequenceAlignmentEngine.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/SequenceAlignmentTests.swift`

- [ ] **Step 1: Write tests**

Test: known history with repeated pattern → prediction matches pattern. Partial week (3 days) finds similar complete weeks. Returns .sequenceAlignment engine type.

- [ ] **Step 2: Implement**

```swift
public struct SequencePrediction: Codable, Sendable {
    public let predictedBedtime: Double
    public let predictedWake: Double
    public let predictedDuration: Double
    public let confidence: Double        // [0,1]
    public let basedOn: [WeekAlignment]
}

public struct WeekAlignment: Codable, Sendable {
    public let weekIndex: Int
    public let startDay: Int
    public let dtwScore: Double
    public let similarity: Double       // 1.0 / (1.0 + dtwScore)
    public let alignmentPath: [(Int, Int)]  // stored as flat array for Codable

    enum CodingKeys: String, CodingKey {
        case weekIndex, startDay, dtwScore, similarity, pathFlat
    }
    // Custom Codable for tuple array
}

public enum SequenceAlignmentEngine {
    /// Predict using partial-week alignment against history
    public static func predict(
        currentDays: [DayNucleotide],
        history: [WeekSequence],
        weights: [Double]?,
        targetDate: Date
    ) -> PredictionOutput? {
        guard currentDays.count >= 2, history.count >= 4 else { return nil }

        // 1. Partial DTW against all historical weeks
        var alignments: [(week: WeekSequence, distance: Double)] = []
        for week in history {
            let (dist, _) = DTWEngine.partialDistance(
                partial: currentDays, full: week, weights: weights
            )
            alignments.append((week, dist))
        }

        // 2. Top 5 most similar
        let top5 = alignments.sorted { $0.distance < $1.distance }.prefix(5)
        guard !top5.isEmpty else { return nil }

        // 3. Weighted average of remaining days
        let currentCount = currentDays.count
        var totalWeight = 0.0
        var bedtimeSum = 0.0, wakeSum = 0.0, durationSum = 0.0

        for (week, distance) in top5 {
            let w = 1.0 / (1.0 + distance)
            // Look at the days after currentCount in the historical week
            if currentCount < week.nucleotides.count {
                let nextDay = week.nucleotides[currentCount]
                // Decode bedtime/wake from sin/cos features
                let bed = atan2(nextDay.features[0], nextDay.features[1]) / (2 * .pi) * 24
                let wake = atan2(nextDay.features[2], nextDay.features[3]) / (2 * .pi) * 24
                let dur = nextDay.features[4] * 12.0
                bedtimeSum += bed * w
                wakeSum += wake * w
                durationSum += dur * w
                totalWeight += w
            }
        }

        guard totalWeight > 0 else { return nil }
        let predictedBed = bedtimeSum / totalWeight
        let predictedWake = wakeSum / totalWeight
        let predictedDur = durationSum / totalWeight

        // Confidence based on best match similarity
        let bestSim = 1.0 / (1.0 + (top5.first?.distance ?? 999))

        return PredictionOutput(
            predictedBedtimeHour: predictedBed < 0 ? predictedBed + 24 : predictedBed,
            predictedWakeHour: predictedWake < 0 ? predictedWake + 24 : predictedWake,
            predictedDuration: predictedDur,
            confidence: bestSim > 0.7 ? .high : bestSim > 0.4 ? .medium : .low,
            engine: .sequenceAlignment,
            targetDate: targetDate
        )
    }
}
```

- [ ] **Step 3: Run tests, build, commit**

---

### Task 11: SleepDNAProfile + SleepDNAComputer

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SleepDNAProfile.swift`
- Create: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/SleepDNAComputer.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/SleepDNA/SleepDNAComputerTests.swift`

- [ ] **Step 1: Create SleepDNAProfile (all types already defined in other files — this is the consolidation struct)**

```swift
public enum AnalysisTier: String, Codable, Sendable {
    case basic          // <4 weeks
    case intermediate   // 4-8 weeks
    case full           // 8+ weeks
}

public struct WeekCluster: Identifiable, Codable, Sendable {
    public let id: UUID
    public let label: String
    public let memberWeekIndices: [Int]
    public let avgQuality: Double
}

public struct SleepDNAProfile: Codable, Sendable {
    public let nucleotides: [DayNucleotide]
    public let sequences: [WeekSequence]
    public let basePairs: [BasePairSynchrony]
    public let motifs: [SleepMotif]
    public let mutations: [SleepMutation]
    public let clusters: [WeekCluster]
    public let expressionRules: [ExpressionRule]
    public let currentWeekSimilar: [WeekAlignment]
    public let prediction: SequencePrediction?
    public let scoringMatrix: SleepBLOSUM
    public let healthMarkers: HealthMarkers
    public let helixGeometry: [DayHelixParams]
    public let tier: AnalysisTier
    public let computedAt: Date
    public let dataWeeks: Int
}
```

- [ ] **Step 2: Write SleepDNAComputer tests**

Test: 7 records → basic tier. 30 records → intermediate. 60 records → full. Cancellation works.

- [ ] **Step 3: Implement SleepDNAComputer**

```swift
public actor SleepDNAComputer {
    private var currentTask: Task<SleepDNAProfile, Error>?

    /// Run full pipeline. Cancels any in-flight computation.
    public func compute(
        records: [SleepRecord],
        events: [CircadianEvent],
        chronotype: ChronotypeResult?,
        goalDuration: Double,
        period: Double = 24,
        existingBLOSUM: SleepBLOSUM? = nil
    ) async throws -> SleepDNAProfile {
        // Cancel previous computation
        currentTask?.cancel()

        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let weeks = records.count / 7
            let tier: AnalysisTier = weeks >= 8 ? .full : weeks >= 4 ? .intermediate : .basic

            // 1. Encode nucleotides
            let nucleotides = records.map { record in
                DayNucleotide(from: record, events: events, period: period, goalDuration: goalDuration)
            }
            try Task.checkCancellation()

            // 2. Generate sequences
            let sequences = WeekSequence.generateSequences(from: nucleotides)
            try Task.checkCancellation()

            // 3. Base pairs (Hilbert)
            let basePairs = tier == .basic
                ? HilbertPhaseAnalyzer.analyze(nucleotides: nucleotides)
                : HilbertPhaseAnalyzer.analyze(nucleotides: nucleotides)
            try Task.checkCancellation()

            // 4. SleepBLOSUM
            let blosum = tier == .full
                ? SleepBLOSUM.learn(from: nucleotides)
                : existingBLOSUM ?? .initial
            try Task.checkCancellation()

            // 5. Motifs (full tier only)
            let motifs = tier == .full
                ? MotifDiscovery.discover(sequences: sequences, weights: blosum.weights)
                : []
            try Task.checkCancellation()

            // 6. Mutations + expression
            let (mutations, rules) = tier == .full
                ? MutationClassifier.classify(nucleotides: nucleotides, motifs: motifs, weights: blosum.weights)
                : ([], [])

            // 7. Health markers
            let health = HealthMarkerDetector.analyze(records: records)

            // 8. Helix geometry
            let geometry = HelixGeometryComputer.compute(
                records: records, basePairs: basePairs, chronotype: chronotype
            )

            // 9. Prediction
            let currentDays = Array(nucleotides.suffix(min(nucleotides.count, 6)))
            let prediction = sequences.count >= 4
                ? SequenceAlignmentEngine.predict(
                    currentDays: currentDays, history: sequences,
                    weights: blosum.weights, targetDate: Date()
                )
                : nil

            return SleepDNAProfile(
                nucleotides: nucleotides, sequences: sequences,
                basePairs: basePairs, motifs: motifs, mutations: mutations,
                clusters: [], expressionRules: rules,
                currentWeekSimilar: [], prediction: prediction.map { _ in SequencePrediction(...) },
                scoringMatrix: blosum, healthMarkers: health,
                helixGeometry: geometry, tier: tier,
                computedAt: Date(), dataWeeks: weeks
            )
        }
        currentTask = task
        return try await task.value
    }
}
```

**Note:** The `SleepDNAProfile` initializer above uses placeholder `...` — the implementer should wire the actual prediction data through.

- [ ] **Step 4: Run tests, build, commit**

---

### Task 12: Integration (PredictionService + Coach + SwiftData)

**Files:**
- Modify: `spiral journey project/Services/PredictionService.swift`
- Modify: `spiral journey project/Services/LLMContextBuilder.swift`
- Create: `spiral journey project/Models/SDSleepDNASnapshot.swift`
- Create: `spiral journey project/Models/SDSleepBLOSUM.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift` (add SD models to container)

- [ ] **Step 1: Create SwiftData models**

```swift
// SDSleepDNASnapshot.swift
@Model final class SDSleepDNASnapshot {
    var computedAt: Date
    var tier: String                    // AnalysisTier.rawValue
    var dataWeeks: Int
    var profileJSON: Data?              // full SleepDNAProfile serialized
    init(computedAt: Date, tier: String, dataWeeks: Int, profileJSON: Data?) { ... }
}

// SDSleepBLOSUM.swift
@Model final class SDSleepBLOSUM {
    var updatedAt: Date
    var weights: String                 // JSON-encoded [Double] (16 elements)
    init(updatedAt: Date, weights: String) { ... }
}
```

- [ ] **Step 2: Add to ModelContainer schema**

In `spiral_journey_projectApp.swift`, add `SDSleepDNASnapshot.self` and `SDSleepBLOSUM.self` to the `allModels` array.

- [ ] **Step 3: Wire alignment engine into PredictionService**

In `PredictionService.generatePrediction()`, after the existing ML/heuristic block:

```swift
// Sequence alignment engine (if enabled and enough data)
if store.sleepDNAPredictionEnabled,
   let dnaProfile = store.latestDNAProfile,
   let alignmentPrediction = dnaProfile.prediction {
    // Use alignment prediction as supplementary signal
    // For now: log it. Full ensemble in future iteration.
    print("[SleepDNA] Alignment prediction: bed \(alignmentPrediction.predictedBedtime)")
}
```

- [ ] **Step 4: Inject DNA insights into coach prompt**

In `LLMContextBuilder.swift`, in the `.rich` capability block, add:

```swift
if let dna = dnaProfile {
    prompt += "\n\nSLEEP DNA ANALYSIS:"
    if !dna.motifs.isEmpty {
        prompt += "\nRecurring patterns: \(dna.motifs.map(\.name).joined(separator: ", "))"
    }
    if let health = dna.healthMarkers, health.circadianCoherence < 0.4 {
        prompt += "\nCircadian stability: low (\(Int(health.circadianCoherence * 100))%)"
    }
    if !dna.currentWeekSimilar.isEmpty {
        let best = dna.currentWeekSimilar.first!
        prompt += "\nThis week is \(Int(best.similarity * 100))% similar to week \(best.weekIndex)"
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 6: Run full test suite**

Run: `cd SpiralKit && swift test 2>&1 | tail -15`

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: integrate SleepDNA with prediction service, coach, and SwiftData

Alignment engine wired into PredictionService (supplementary signal).
DNA insights injected into coach system prompt (rich tier).
SDSleepDNASnapshot and SDSleepBLOSUM for persistence."
```

---

## Final Verification

After all tasks complete:

- [ ] `cd SpiralKit && swift test` — all tests pass (existing 294 + new SleepDNA tests)
- [ ] `xcodebuild build -scheme "spiral journey project" ...` — iOS builds
- [ ] `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS` — Watch builds
- [ ] Verify SleepDNA module compiles on watchOS target (no RealityKit/UIKit imports)
- [ ] Run app in simulator — no crash, existing features unaffected
