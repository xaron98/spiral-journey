# Lomb-Scargle Periodogram Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Lomb-Scargle periodogram analysis to detect dominant biological rhythms (circadian, weekly, menstrual) and display them in an interactive chart panel in the Analysis tab.

**Architecture:** Pure-math `LombScargle` enum in SpiralKit (no UI deps), a `PeriodogramView` in the app using Swift Charts, and integration via `AnalysisResult.periodograms` computed inside `SpiralStore.recompute()`.

**Tech Stack:** Swift, SpiralKit, Swift Charts (iOS 16+), SwiftUI

**Spec:** `docs/superpowers/specs/2026-03-23-lomb-scargle-periodogram-design.md`

**Build command:** `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

**SpiralKit test command:** `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift` | Core algorithm + signal extraction + peak detection |
| Create | `SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift` | Unit tests for engine |
| Modify | `SpiralKit/Sources/SpiralKit/Models/AnalysisResult.swift` | Add `periodograms` field |
| Modify | `spiral journey project/Services/SpiralStore.swift` | Compute periodograms in `recompute()` |
| Create | `spiral journey project/Views/Charts/PeriodogramView.swift` | Swift Charts panel + signal picker + insights |
| Modify | `spiral journey project/Views/Tabs/AnalysisTab.swift` | Add toggle + embed PeriodogramView |
| Modify | `spiral journey project/Localizable.xcstrings` | Add localization keys (9 languages) |

---

## Chunk 1: LombScargle Engine + Tests

### Task 1: Core algorithm — compute()

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift`

- [ ] **Step 1: Write failing test — pure 24h sinusoid produces dominant peak**

```swift
import Testing
@testable import SpiralKit

@Suite("LombScargle Tests")
struct LombScargleTests {

    @Test("Pure 24h sinusoid produces dominant circadian peak")
    func pure24hSinusoid() {
        // Generate 30 days of data with a clean 24h sinusoidal signal
        var times: [Double] = []
        var values: [Double] = []
        for day in 0..<30 {
            let t = Double(day) * 24.0
            times.append(t)
            values.append(sin(2 * .pi * t / 24.0))
        }

        let result = LombScargle.compute(
            times: times, values: values, signal: .sleepMidpoint
        )

        #expect(!result.peaks.isEmpty, "Should detect at least one peak")
        let topPeak = result.peaks[0]
        #expect(topPeak.isSignificant, "Top peak should be significant")
        #expect(abs(topPeak.period - 24.0) < 2.0, "Dominant period should be ~24h, got \(topPeak.period)")
        #expect(topPeak.label == .circadian, "Should be labeled circadian")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test --filter LombScargleTests`
Expected: FAIL — `LombScargle` type not found

- [ ] **Step 3: Implement LombScargle.compute() with types**

```swift
import Foundation

/// Lomb-Scargle periodogram for detecting dominant rhythms in irregularly sampled data.
///
/// Detects circadian (24h), circaseptano (7d), bisemanal (14d), and circalunar (28d)
/// periodicities from sleep and health time series.
///
/// References:
///   - Lomb (1976). Least-squares frequency analysis of unequally spaced data.
///   - Scargle (1982). Studies in astronomical time series analysis.
public enum LombScargle {

    // MARK: - Types

    public enum Signal: String, CaseIterable, Codable, Sendable {
        case sleepMidpoint
        case sleepDuration
        case cosinorAmplitude
        case restingHR
        case nocturnalHRV
    }

    public enum PeakLabel: String, Codable, Sendable {
        case circadian   // 24h ± 2h
        case weekly      // 168h ± 12h
        case biweekly    // 336h ± 24h
        case menstrual   // 672h ± 48h
    }

    public struct Peak: Codable, Sendable {
        public let period: Double
        public let power: Double
        public let isSignificant: Bool
        public let label: PeakLabel?

        public init(period: Double, power: Double, isSignificant: Bool, label: PeakLabel?) {
            self.period = period
            self.power = power
            self.isSignificant = isSignificant
            self.label = label
        }
    }

    public struct PeriodogramResult: Codable, Sendable {
        public let signal: Signal
        public let frequencies: [Double]
        public let powers: [Double]
        public let significanceThreshold: Double
        public let peaks: [Peak]

        public init(signal: Signal, frequencies: [Double] = [], powers: [Double] = [],
                    significanceThreshold: Double = 0, peaks: [Peak] = []) {
            self.signal = signal
            self.frequencies = frequencies
            self.powers = powers
            self.significanceThreshold = significanceThreshold
            self.peaks = peaks
        }

        public static func empty(signal: Signal) -> PeriodogramResult {
            PeriodogramResult(signal: signal)
        }
    }

    // MARK: - Core Algorithm

    public static func compute(
        times: [Double],
        values: [Double],
        signal: Signal,
        minPeriod: Double = 12,
        maxPeriod: Double = 720,
        numFreqs: Int = 500
    ) -> PeriodogramResult {
        let n = times.count
        guard n >= 14 else { return .empty(signal: signal) }
        guard minPeriod < maxPeriod, numFreqs > 0 else { return .empty(signal: signal) }

        // Mean-center
        let mean = values.reduce(0, +) / Double(n)
        let centered = values.map { $0 - mean }
        let variance = centered.map { $0 * $0 }.reduce(0, +) / Double(n)
        guard variance > 1e-12 else { return .empty(signal: signal) }

        // Frequency grid: linearly spaced in period
        let periodStep = (maxPeriod - minPeriod) / Double(numFreqs)
        var frequencies: [Double] = []
        var powers: [Double] = []

        for i in 0..<numFreqs {
            let period = minPeriod + Double(i) * periodStep
            let freq = 1.0 / period
            let omega = 2 * Double.pi * freq

            // Phase offset τ
            var sin2sum = 0.0, cos2sum = 0.0
            for t in times {
                sin2sum += sin(2 * omega * t)
                cos2sum += cos(2 * omega * t)
            }
            let tau = atan2(sin2sum, cos2sum) / (2 * omega)

            // Power
            var cosSum = 0.0, sinSum = 0.0
            var cos2 = 0.0, sin2 = 0.0
            for j in 0..<n {
                let phase = omega * (times[j] - tau)
                let c = cos(phase)
                let s = sin(phase)
                cosSum += centered[j] * c
                sinSum += centered[j] * s
                cos2 += c * c
                sin2 += s * s
            }

            let denom1 = cos2 > 1e-12 ? cos2 : 1e-12
            let denom2 = sin2 > 1e-12 ? sin2 : 1e-12
            let power = (cosSum * cosSum / denom1 + sinSum * sinSum / denom2) / (2 * variance)

            frequencies.append(freq)
            powers.append(power)
        }

        // Significance threshold: Bonferroni-corrected p < 0.01
        let m = Double(numFreqs)
        let threshold = -log(1.0 - pow(1.0 - 0.01, 1.0 / m))

        // Peak detection
        let peaks = detectPeaks(
            frequencies: frequencies, powers: powers,
            minPeriod: minPeriod, periodStep: periodStep,
            threshold: threshold
        )

        return PeriodogramResult(
            signal: signal,
            frequencies: frequencies,
            powers: powers,
            significanceThreshold: threshold,
            peaks: peaks
        )
    }

    // MARK: - Peak Detection

    private static func detectPeaks(
        frequencies: [Double], powers: [Double],
        minPeriod: Double, periodStep: Double,
        threshold: Double
    ) -> [Peak] {
        var peaks: [Peak] = []
        for i in 1..<(powers.count - 1) {
            guard powers[i] > powers[i - 1], powers[i] > powers[i + 1] else { continue }
            guard powers[i] > threshold else { continue }
            let period = minPeriod + Double(i) * periodStep
            let label = labelForPeriod(period)
            peaks.append(Peak(period: period, power: powers[i], isSignificant: true, label: label))
        }
        return peaks.sorted { $0.power > $1.power }
    }

    private static func labelForPeriod(_ period: Double) -> PeakLabel? {
        if abs(period - 24) < 2          { return .circadian }
        if abs(period - 168) < 12        { return .weekly }
        if abs(period - 336) < 24        { return .biweekly }
        if abs(period - 672) < 48        { return .menstrual }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test --filter LombScargleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift
git commit -m "feat: add LombScargle engine with core compute and peak detection"
```

---

### Task 2: Additional algorithm tests

**Files:**
- Modify: `SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift`

- [ ] **Step 1: Write tests for edge cases and composite signals**

Add to `LombScargleTests`:

```swift
@Test("Composite 24h + 168h signal detects two peaks")
func compositeTwoPeaks() {
    var times: [Double] = []
    var values: [Double] = []
    for day in 0..<60 {
        let t = Double(day) * 24.0
        times.append(t)
        // 24h component + 7d component
        let circadian = sin(2 * .pi * t / 24.0)
        let weekly = 0.5 * sin(2 * .pi * t / 168.0)
        values.append(circadian + weekly)
    }

    let result = LombScargle.compute(
        times: times, values: values, signal: .sleepDuration
    )

    let labels = result.peaks.compactMap(\.label)
    #expect(labels.contains(.circadian), "Should detect circadian peak")
    #expect(labels.contains(.weekly), "Should detect weekly peak")
}

@Test("Flat signal produces no peaks")
func flatSignal() {
    let times = (0..<30).map { Double($0) * 24.0 }
    let values = Array(repeating: 5.0, count: 30)

    let result = LombScargle.compute(
        times: times, values: values, signal: .sleepDuration
    )

    #expect(result.peaks.isEmpty, "Flat signal should have no peaks")
    #expect(result.frequencies.isEmpty, "Flat signal should return empty result")
}

@Test("Fewer than 14 data points returns empty result")
func insufficientData() {
    let times = (0..<10).map { Double($0) * 24.0 }
    let values = (0..<10).map { sin(2 * .pi * Double($0) * 24.0 / 24.0) }

    let result = LombScargle.compute(
        times: times, values: values, signal: .sleepMidpoint
    )

    #expect(result.peaks.isEmpty)
    #expect(result.frequencies.isEmpty)
}

@Test("Known period with noise detected within ±2h")
func noisySignal() {
    var times: [Double] = []
    var values: [Double] = []
    // Use seeded pseudo-random noise for determinism
    var rng: UInt64 = 42
    for day in 0..<45 {
        let t = Double(day) * 24.0
        times.append(t)
        // SplitMix64 for deterministic noise
        rng &+= 0x9e3779b97f4a7c15
        var z = rng
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        let noise = (Double(z) / Double(UInt64.max) - 0.5) * 0.5
        values.append(sin(2 * .pi * t / 24.0) + noise)
    }

    let result = LombScargle.compute(
        times: times, values: values, signal: .sleepMidpoint
    )

    #expect(!result.peaks.isEmpty, "Should still detect peak through noise")
    #expect(abs(result.peaks[0].period - 24.0) < 2.0, "Peak should be near 24h")
}

@Test("Deterministic: same input produces same output")
func deterministic() {
    let times = (0..<30).map { Double($0) * 24.0 }
    let values = times.map { sin(2 * .pi * $0 / 168.0) + 0.3 * sin(2 * .pi * $0 / 24.0) }

    let r1 = LombScargle.compute(times: times, values: values, signal: .sleepDuration)
    let r2 = LombScargle.compute(times: times, values: values, signal: .sleepDuration)

    #expect(r1.powers == r2.powers, "Same input must produce identical powers")
    #expect(r1.peaks.count == r2.peaks.count)
}

@Test("Invalid parameters return empty result")
func invalidParams() {
    let times = (0..<30).map { Double($0) * 24.0 }
    let values = times.map { sin(2 * .pi * $0 / 24.0) }

    let r1 = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint, minPeriod: 100, maxPeriod: 50)
    #expect(r1.frequencies.isEmpty, "minPeriod >= maxPeriod should give empty result")

    let r2 = LombScargle.compute(times: times, values: values, signal: .sleepMidpoint, numFreqs: 0)
    #expect(r2.frequencies.isEmpty, "numFreqs=0 should give empty result")
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test --filter LombScargleTests`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift
git commit -m "test: add edge case and composite signal tests for LombScargle"
```

---

### Task 3: Signal extraction — analyze() and analyzeAll()

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift`
- Modify: `SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift`

- [ ] **Step 1: Write failing test for sleep midpoint extraction with unwrapping**

Add to `LombScargleTests`:

```swift
// MARK: - Helpers

private func makeRecord(day: Int, bedtime: Double, wake: Double, duration: Double, amplitude: Double = 0.5) -> SleepRecord {
    SleepRecord(
        day: day, date: Date(), isWeekend: day % 7 >= 5,
        bedtimeHour: bedtime, wakeupHour: wake, sleepDuration: duration,
        phases: [],
        hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
        cosinor: CosinorResult(mesor: 0.5, amplitude: amplitude, acrophase: 14, period: 24, r2: 0.5)
    )
}

@Test("Sleep midpoint handles midnight wrap — bedtime 23, wake 7 → midpoint 3")
func midpointWrap() {
    let records = (0..<20).map { day in
        makeRecord(day: day, bedtime: 23, wake: 7, duration: 8)
    }
    let result = LombScargle.analyze(records, signal: .sleepMidpoint)
    // All midpoints are 3.0 (constant) → flat → no peaks
    #expect(result.peaks.isEmpty, "Constant midpoint should yield no peaks")
}

@Test("Sleep midpoint unwrapping preserves drift across midnight")
func midpointUnwrapping() {
    // Simulate gradual drift: midpoint goes 23 → 0 → 1 → 2 over days
    // This is a Non-24 pattern (advancing ~1h per day)
    let records = (0..<30).map { day in
        let midpoint = (23.0 + Double(day)) .truncatingRemainder(dividingBy: 24)
        // Work backwards to get bedtime/wake from midpoint
        let bedtime = (midpoint - 4).truncatingRemainder(dividingBy: 24)
        let wake = (midpoint + 4).truncatingRemainder(dividingBy: 24)
        return makeRecord(day: day, bedtime: bedtime < 0 ? bedtime + 24 : bedtime,
                         wake: wake, duration: 8)
    }
    let result = LombScargle.analyze(records, signal: .sleepMidpoint)
    // With unwrapping, this is a linear ramp — Lomb-Scargle should see a ~24h period
    // (the drift completes one full cycle in 24 days)
    #expect(!result.peaks.isEmpty, "Drifting midpoint should produce a peak")
}

@Test("analyze with < 14 records returns empty")
func analyzeInsufficientRecords() {
    let records = (0..<10).map { day in
        makeRecord(day: day, bedtime: 23, wake: 7, duration: 8)
    }
    let result = LombScargle.analyze(records, signal: .sleepDuration)
    #expect(result.peaks.isEmpty)
    #expect(result.frequencies.isEmpty)
}

@Test("All Signal cases produce valid extraction")
func allSignalsExtract() {
    let records = (0..<20).map { day in
        makeRecord(day: day, bedtime: 23, wake: 7, duration: 7 + sin(2 * .pi * Double(day) / 7.0))
    }
    for signal in [LombScargle.Signal.sleepMidpoint, .sleepDuration, .cosinorAmplitude] {
        let result = LombScargle.analyze(records, signal: signal)
        // Should at least not crash — duration should show a peak
        #expect(result.signal == signal)
    }
}

@Test("analyzeAll skips HR/HRV when no health profiles provided")
func analyzeAllSkipsHealthSignals() {
    let records = (0..<20).map { day in
        makeRecord(day: day, bedtime: 23, wake: 7, duration: 8)
    }
    let results = LombScargle.analyzeAll(records)
    #expect(results[.sleepMidpoint] != nil)
    #expect(results[.sleepDuration] != nil)
    #expect(results[.cosinorAmplitude] != nil)
    #expect(results[.restingHR] == nil, "No health profiles → no restingHR")
    #expect(results[.nocturnalHRV] == nil, "No health profiles → no nocturnalHRV")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test --filter LombScargleTests`
Expected: FAIL — `analyze` and `analyzeAll` not found

- [ ] **Step 3: Implement signal extraction methods**

Add to `LombScargle.swift`, after the `compute` method:

```swift
// MARK: - Signal Extraction

public static func analyze(
    _ records: [SleepRecord],
    signal: Signal,
    healthProfiles: [DayHealthProfile] = []
) -> PeriodogramResult {
    let (times, values) = extractSignal(signal, records: records, healthProfiles: healthProfiles)
    guard times.count >= 14 else { return .empty(signal: signal) }
    return compute(times: times, values: values, signal: signal)
}

public static func analyzeAll(
    _ records: [SleepRecord],
    healthProfiles: [DayHealthProfile] = []
) -> [Signal: PeriodogramResult] {
    guard records.count >= 14 else { return [:] }
    var results: [Signal: PeriodogramResult] = [:]

    // Sleep-based signals (always available)
    for signal in [Signal.sleepMidpoint, .sleepDuration, .cosinorAmplitude] {
        results[signal] = analyze(records, signal: signal)
    }

    // Health-based signals (only if enough data)
    let hrCount = healthProfiles.compactMap(\.restingHR).count
    if hrCount >= 14 {
        results[.restingHR] = analyze(records, signal: .restingHR, healthProfiles: healthProfiles)
    }
    let hrvCount = healthProfiles.compactMap(\.avgNocturnalHRV).count
    if hrvCount >= 14 {
        results[.nocturnalHRV] = analyze(records, signal: .nocturnalHRV, healthProfiles: healthProfiles)
    }

    return results
}

// MARK: - Private Extraction

private static func extractSignal(
    _ signal: Signal,
    records: [SleepRecord],
    healthProfiles: [DayHealthProfile]
) -> (times: [Double], values: [Double]) {
    switch signal {
    case .sleepMidpoint:
        return extractSleepMidpoint(records)
    case .sleepDuration:
        let times = records.map { Double($0.day) * 24.0 }
        let values = records.map(\.sleepDuration)
        return (times, values)
    case .cosinorAmplitude:
        let times = records.map { Double($0.day) * 24.0 }
        let values = records.map(\.cosinor.amplitude)
        return (times, values)
    case .restingHR:
        return extractHealthSignal(healthProfiles, keyPath: \.restingHR)
    case .nocturnalHRV:
        return extractHealthSignal(healthProfiles, keyPath: \.avgNocturnalHRV)
    }
}

private static func extractSleepMidpoint(_ records: [SleepRecord]) -> (times: [Double], values: [Double]) {
    // Step 1: Compute circular midpoint per day
    var midpoints: [Double] = []
    var times: [Double] = []
    for record in records {
        let bed = record.bedtimeHour
        let wake = record.wakeupHour
        let rawMid = (bed + wake) / 2.0
        let midpoint: Double
        if wake < bed {
            midpoint = (rawMid + 12).truncatingRemainder(dividingBy: 24)
        } else {
            midpoint = rawMid
        }
        midpoints.append(midpoint)
        times.append(Double(record.day) * 24.0)
    }

    guard !midpoints.isEmpty else { return ([], []) }

    // Step 2: Phase unwrap to continuous signal
    var unwrapped = [midpoints[0]]
    for i in 1..<midpoints.count {
        var delta = midpoints[i] - midpoints[i - 1]
        if delta > 12 { delta -= 24 }
        if delta < -12 { delta += 24 }
        unwrapped.append(unwrapped[i - 1] + delta)
    }

    return (times, unwrapped)
}

private static func extractHealthSignal(
    _ profiles: [DayHealthProfile],
    keyPath: KeyPath<DayHealthProfile, Double?>
) -> (times: [Double], values: [Double]) {
    var times: [Double] = []
    var values: [Double] = []
    for profile in profiles {
        if let value = profile[keyPath: keyPath] {
            times.append(Double(profile.day) * 24.0)
            values.append(value)
        }
    }
    return (times, values)
}
```

- [ ] **Step 4: Run all tests**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test --filter LombScargleTests`
Expected: ALL PASS

- [ ] **Step 5: Run full SpiralKit suite to check for regressions**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test`
Expected: ALL PASS (485+ tests)

- [ ] **Step 6: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift SpiralKit/Tests/SpiralKitTests/LombScargleTests.swift
git commit -m "feat: add signal extraction (analyze/analyzeAll) with midpoint unwrapping"
```

---

## Chunk 2: AnalysisResult + SpiralStore Integration

### Task 4: Add periodograms to AnalysisResult

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Models/AnalysisResult.swift:202-250`

- [ ] **Step 1: Add periodograms property and init parameter**

In `AnalysisResult` struct, after `enhancedCoach` (line 221):

```swift
/// Lomb-Scargle periodogram results per signal. nil when < 14 days of data.
/// Optional to preserve backward-compatible Codable decoding (existing encoded data lacks this key).
public var periodograms: [LombScargle.Signal: LombScargle.PeriodogramResult]?
```

In the `init`, add parameter after `enhancedCoach` (line 235):

```swift
periodograms: [LombScargle.Signal: LombScargle.PeriodogramResult]? = nil
```

In the init body, after `self.enhancedCoach = enhancedCoach` (line 248):

```swift
self.periodograms = periodograms
```

- [ ] **Step 2: Build SpiralKit to verify**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Models/AnalysisResult.swift
git commit -m "feat: add periodograms field to AnalysisResult"
```

---

### Task 5: Compute periodograms in SpiralStore.recompute()

**Files:**
- Modify: `spiral journey project/Services/SpiralStore.swift:521-627`

- [ ] **Step 1: Capture healthProfiles before Task.detached**

At line 546 (after `let currentEvents = events`), add:

```swift
let hp = healthProfiles
```

- [ ] **Step 2: Compute periodograms inside the detached task**

After line 574 (after the `if blocksEnabled` else block closes, before `await MainActor.run`), add:

```swift
// Lomb-Scargle periodogram (requires ≥14 days)
let newPeriodograms: [LombScargle.Signal: LombScargle.PeriodogramResult]?
if newRecords.count >= 14 {
    newPeriodograms = LombScargle.analyzeAll(newRecords, healthProfiles: hp)
} else {
    newPeriodograms = nil
}
```

- [ ] **Step 3: Assign in MainActor.run**

After line 578 (`self.analysis = newAnalysis`), add:

```swift
self.analysis.periodograms = newPeriodograms
```

- [ ] **Step 4: Build the full app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add "spiral journey project/Services/SpiralStore.swift"
git commit -m "feat: compute periodograms in SpiralStore.recompute()"
```

---

## Chunk 3: PeriodogramView + AnalysisTab Integration

### Task 6: Create PeriodogramView

**Files:**
- Create: `spiral journey project/Views/Charts/PeriodogramView.swift`

- [ ] **Step 1: Create the view file**

```swift
import SwiftUI
import Charts
import SpiralKit

/// Periodogram chart showing dominant rhythms detected via Lomb-Scargle analysis.
/// Signal picker lets the user switch between sleep midpoint, duration, amplitude, HR, and HRV.
struct PeriodogramView: View {

    let periodograms: [LombScargle.Signal: LombScargle.PeriodogramResult]?
    let healthProfiles: [DayHealthProfile]
    let recordCount: Int

    @Environment(\.languageBundle) private var bundle
    @State private var selectedSignal: LombScargle.Signal = .sleepMidpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "periodogram.title", bundle: bundle))

            if recordCount < 14 {
                insufficientDataView
            } else if let result = periodograms?[selectedSignal] {
                signalPicker
                if result.frequencies.isEmpty {
                    noDataForSignalView
                } else {
                    chartView(result)
                    peakList(result)
                    insightText(result)
                }
            } else {
                signalPicker
                noDataForSignalView
            }
        }
        .glassPanel()
    }

    // MARK: - Signal Picker

    private var availableSignals: [LombScargle.Signal] {
        var signals: [LombScargle.Signal] = [.sleepMidpoint, .sleepDuration, .cosinorAmplitude]
        if periodograms?[.restingHR] != nil { signals.append(.restingHR) }
        if periodograms?[.nocturnalHRV] != nil { signals.append(.nocturnalHRV) }
        return signals
    }

    private var signalPicker: some View {
        Picker(String(localized: "periodogram.signal", bundle: bundle), selection: $selectedSignal) {
            ForEach(availableSignals, id: \.self) { signal in
                Text(signalLabel(signal)).tag(signal)
            }
        }
        .pickerStyle(.menu)
    }

    private func signalLabel(_ signal: LombScargle.Signal) -> String {
        switch signal {
        case .sleepMidpoint:    return String(localized: "periodogram.signal.midpoint", bundle: bundle)
        case .sleepDuration:    return String(localized: "periodogram.signal.duration", bundle: bundle)
        case .cosinorAmplitude: return String(localized: "periodogram.signal.amplitude", bundle: bundle)
        case .restingHR:        return String(localized: "periodogram.signal.restingHR", bundle: bundle)
        case .nocturnalHRV:     return String(localized: "periodogram.signal.nocturnalHRV", bundle: bundle)
        }
    }

    // MARK: - Chart

    private struct ChartPoint: Identifiable {
        let id: Int
        let period: Double   // hours
        let power: Double
    }

    private func chartView(_ result: LombScargle.PeriodogramResult) -> some View {
        let points = result.frequencies.enumerated().map { (i, freq) in
            ChartPoint(id: i, period: 1.0 / freq, power: result.powers[i])
        }
        let maxPower = result.powers.max() ?? 1

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Period", point.period),
                    y: .value("Power", point.power)
                )
                .foregroundStyle(.blue.opacity(0.3))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Period", point.period),
                    y: .value("Power", point.power)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            // Significance threshold
            RuleMark(y: .value("Threshold", result.significanceThreshold))
                .foregroundStyle(.red.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .annotation(position: .trailing, alignment: .leading) {
                    Text(String(localized: "periodogram.threshold", bundle: bundle))
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.6))
                }
            // Peak markers
            ForEach(result.peaks.indices, id: \.self) { i in
                let peak = result.peaks[i]
                PointMark(
                    x: .value("Period", peak.period),
                    y: .value("Power", peak.power)
                )
                .foregroundStyle(.orange)
                .symbolSize(40)
            }
        }
        .chartXScale(type: .log)
        .chartYScale(domain: 0...(maxPower * 1.1))
        .chartXAxis {
            AxisMarks(values: [12, 24, 168, 336, 672]) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(formatAxisPeriod(value.as(Double.self) ?? 0))
                }
            }
        }
        .chartYAxisLabel(String(localized: "periodogram.axis.power", bundle: bundle))
        .frame(height: 180)
    }

    // MARK: - Peak List

    private func peakList(_ result: LombScargle.PeriodogramResult) -> some View {
        let maxPower = result.peaks.first?.power ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            if result.peaks.isEmpty {
                Text(String(localized: "periodogram.noPeaks", bundle: bundle))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            } else {
                ForEach(result.peaks.indices, id: \.self) { i in
                    let peak = result.peaks[i]
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text(peakLabel(peak))
                            .font(.caption)
                        Spacer()
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.orange.opacity(0.4))
                                .frame(width: geo.size.width * (peak.power / maxPower))
                        }
                        .frame(width: 60, height: 8)
                        Text(String(format: "%.2f", peak.power))
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func peakLabel(_ peak: LombScargle.Peak) -> String {
        let periodStr: String
        if peak.period < 48 {
            periodStr = String(format: "%.1fh", peak.period)
        } else {
            periodStr = String(format: "%.1f", peak.period / 24.0)
                + " " + String(localized: "periodogram.days", bundle: bundle)
        }

        if let label = peak.label {
            let name: String
            switch label {
            case .circadian: name = String(localized: "periodogram.peak.circadian", bundle: bundle)
            case .weekly:    name = String(localized: "periodogram.peak.weekly", bundle: bundle)
            case .biweekly:  name = String(localized: "periodogram.peak.biweekly", bundle: bundle)
            case .menstrual: name = String(localized: "periodogram.peak.menstrual", bundle: bundle)
            }
            return "\(name) — \(periodStr)"
        }
        return periodStr
    }

    // MARK: - Insight Text

    private func insightText(_ result: LombScargle.PeriodogramResult) -> some View {
        Text(generateInsight(result))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func generateInsight(_ result: LombScargle.PeriodogramResult) -> String {
        guard let topPeak = result.peaks.first else {
            return String(localized: "periodogram.insight.noPeaks", bundle: bundle)
        }
        switch (result.signal, topPeak.label) {
        case (.sleepMidpoint, .circadian):
            return String(localized: "periodogram.insight.midpoint.circadian", bundle: bundle)
        case (.sleepDuration, .weekly):
            return String(localized: "periodogram.insight.duration.weekly", bundle: bundle)
        case (.sleepDuration, .menstrual):
            let hasMenstrualData = healthProfiles.filter { ($0.menstrualFlow ?? 0) > 0 }.count >= 3
            if hasMenstrualData {
                return String(localized: "periodogram.insight.duration.menstrual.withData", bundle: bundle)
            }
            return String(localized: "periodogram.insight.duration.menstrual.noData", bundle: bundle)
        default:
            let periodStr = topPeak.period < 48
                ? String(format: "%.0fh", topPeak.period)
                : String(format: "%.1f d", topPeak.period / 24.0)
            return String(localized: "periodogram.insight.generic \(periodStr)", bundle: bundle)
        }
    }

    // MARK: - Empty States

    private var insufficientDataView: some View {
        VStack(spacing: 4) {
            Text(String(localized: "periodogram.insufficientData", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
            Text("\(recordCount)/14")
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private func formatAxisPeriod(_ hours: Double) -> String {
        if hours < 48 { return String(format: "%.0fh", hours) }
        return String(format: "%.0fd", hours / 24.0)
    }

    private var noDataForSignalView: some View {
        Text(String(localized: "periodogram.noDataForSignal", bundle: bundle))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED (view is not referenced yet, but should compile)

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/Charts/PeriodogramView.swift"
git commit -m "feat: add PeriodogramView with Swift Charts, signal picker, and insights"
```

---

### Task 7: Integrate into AnalysisTab

**Files:**
- Modify: `spiral journey project/Views/Tabs/AnalysisTab.swift`

- [ ] **Step 1: Add toggle state**

After line 22 (`@State private var showHRV = false`), add:

```swift
@State private var showPeriodogram   = false
```

- [ ] **Step 2: Add conditional view**

After line 83 (`if showHRV { HRVTrendView(...) }`), add:

```swift
if showPeriodogram {
    PeriodogramView(
        periodograms: store.analysis.periodograms,
        healthProfiles: store.healthProfiles,
        recordCount: store.records.count
    )
}
```

- [ ] **Step 3: Add toggle button**

After the HRV `PillButton` block (around line 422), add:

```swift
PillButton(
    label: String(localized: "analysis.charts.periodogram", bundle: bundle),
    isActive: showPeriodogram
) {
    showPeriodogram.toggle()
}
```

- [ ] **Step 4: Build the full app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add "spiral journey project/Views/Tabs/AnalysisTab.swift"
git commit -m "feat: add periodogram toggle and view to AnalysisTab"
```

---

### Task 8: Localization strings

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

- [ ] **Step 1: Add all periodogram localization keys**

Add entries to `Localizable.xcstrings` for all 9 languages. The keys needed are:

```
periodogram.title
periodogram.signal
periodogram.signal.midpoint
periodogram.signal.duration
periodogram.signal.amplitude
periodogram.signal.restingHR
periodogram.signal.nocturnalHRV
periodogram.axis.period
periodogram.axis.power
periodogram.days
periodogram.peak.circadian
periodogram.peak.weekly
periodogram.peak.biweekly
periodogram.peak.menstrual
periodogram.noPeaks
periodogram.insufficientData
periodogram.noDataForSignal
periodogram.insight.noPeaks
periodogram.insight.midpoint.circadian
periodogram.insight.duration.weekly
periodogram.insight.duration.menstrual.withData
periodogram.insight.duration.menstrual.noData
periodogram.insight.generic %@
analysis.charts.periodogram
```

Translations for the primary languages:

| Key | en | es | ca |
|-----|----|----|-----|
| periodogram.title | Detected Rhythms | Ritmos Detectados | Ritmes Detectats |
| periodogram.signal | Signal | Señal | Senyal |
| periodogram.signal.midpoint | Sleep Midpoint | Punto medio del sueño | Punt mitjà del son |
| periodogram.signal.duration | Duration | Duración | Durada |
| periodogram.signal.amplitude | Rhythm Strength | Fuerza del ritmo | Força del ritme |
| periodogram.signal.restingHR | Resting HR | FC en reposo | FC en repòs |
| periodogram.signal.nocturnalHRV | Nocturnal HRV | VFC nocturna | VFC nocturna |
| periodogram.peak.circadian | Circadian | Circadiano | Circadià |
| periodogram.peak.weekly | Weekly | Semanal | Setmanal |
| periodogram.peak.biweekly | Biweekly | Bisemanal | Bisetmanal |
| periodogram.peak.menstrual | Menstrual | Menstrual | Menstrual |
| periodogram.noPeaks | No significant rhythms detected in this signal. | No se detectan ritmos significativos en esta señal. | No es detecten ritmes significatius en aquest senyal. |
| periodogram.insufficientData | You need at least 2 weeks of data to detect rhythms. | Necesitas al menos 2 semanas de datos para detectar ritmos. | Necessites almenys 2 setmanes de dades per detectar ritmes. |
| periodogram.insight.midpoint.circadian | Your circadian rhythm is stable at ~24h — well synchronized. | Tu ritmo circadiano es estable a ~24h — bien sincronizado. | El teu ritme circadià és estable a ~24h — ben sincronitzat. |
| periodogram.insight.duration.weekly | Your sleep duration varies with a weekly cycle — likely due to weekday/weekend differences. | Tu duración de sueño varía con un ciclo semanal — probablemente por diferencias entre semana y fines de semana. | La teva durada de son varia amb un cicle setmanal — probablement per diferències entre setmana i cap de setmana. |
| periodogram.threshold | Significance | Significancia | Significança |
| periodogram.noDataForSignal | No data available for this signal. | No hay datos disponibles para esta señal. | No hi ha dades disponibles per a aquest senyal. |
| analysis.charts.periodogram | Rhythms | Ritmos | Ritmes |

(de, fr, zh, ja, ar translations should also be added following the same pattern.)

- [ ] **Step 2: Build to verify localization compiles**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Localizable.xcstrings"
git commit -m "feat: add periodogram localization keys for all 9 languages"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run full SpiralKit test suite**

Run: `cd /Users/xaron/Desktop/spiral\ journey\ project/SpiralKit && swift test`
Expected: ALL PASS (485 + new LombScargle tests)

- [ ] **Step 2: Build the complete app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit (if any fixes were needed)**

Only if steps 1-2 required fixes.
