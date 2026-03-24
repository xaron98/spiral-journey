# Lomb-Scargle Periodogram — Fase B Design Spec

## Overview

Add frequency-domain analysis to Spiral Journey via the Lomb-Scargle periodogram. Detects dominant rhythms (circadian 24h, circaseptano 7d, bisemanal 14d, circalunar 28d) in irregularly sampled sleep and health data. Presents results in an informative panel within the Analysis tab using Swift Charts.

**Goals:**
- Detect dominant biological rhythms across multiple physiological signals
- Present results in human-readable form with labeled peaks and plain-language insights
- Handle missing data gracefully (Lomb-Scargle works natively with irregular sampling)
- Gate by data availability: ≥14 days for periodogram, HR/HRV signals only when DayHealthProfile data exists

**Non-goals (deferred):**
- τ→spiral mapping (changing spiral period based on detected τ) — YAGNI for now, most users are entrained to 24h
- Interactive period reconfiguration (tap peak → change spiral)
- Cross-correlation between signals (Fase C territory)

## Architecture

### Component 1: LombScargle Engine (SpiralKit)

**File:** `SpiralKit/Sources/SpiralKit/Analysis/LombScargle.swift`

**Pattern:** Stateless enum with static functions (follows CosinorAnalysis pattern).

**Dependencies:** None (pure math, no HealthKit or UI imports).

#### Signals

| Signal | Source | Detects | Extraction |
|--------|--------|---------|------------|
| `sleepMidpoint` | SleepRecord | τ circadian, Non-24 drift | `(bedtimeHour + wakeupHour) / 2`, circular-aware |
| `sleepDuration` | SleepRecord | Weekly (social jetlag), menstrual | `sleepDuration` directly |
| `cosinorAmplitude` | SleepRecord | Rhythm strength oscillation | `cosinor.amplitude` |
| `restingHR` | DayHealthProfile | Autonomic cardiovascular rhythm | `restingHR`, skip nil days |
| `nocturnalHRV` | DayHealthProfile | Recovery/stress cycles | `avgNocturnalHRV`, skip nil days |

#### Public Interface

```swift
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
        public let period: Double          // hours
        public let power: Double           // normalized power
        public let isSignificant: Bool     // power > threshold (p < 0.01)
        public let label: PeakLabel?       // nil for unlabeled peaks (shown as raw period)
    }

    public struct PeriodogramResult: Codable, Sendable {
        public let signal: Signal
        public let frequencies: [Double]   // 1/hours
        public let powers: [Double]        // normalized power at each frequency
        public let significanceThreshold: Double
        public let peaks: [Peak]           // significant peaks, sorted by power descending
    }

    // MARK: - Core Algorithm

    /// Compute Lomb-Scargle periodogram from irregularly sampled time series.
    ///
    /// - Parameters:
    ///   - times: Timestamps in hours from day 0. Gaps are handled natively.
    ///   - values: Measured values at each timestamp.
    ///   - minPeriod: Minimum period to scan (hours). Default 12h.
    ///   - maxPeriod: Maximum period to scan (hours). Default 720h (30 days).
    ///   - numFreqs: Number of frequency bins. Default 500.
    /// - Returns: Periodogram result with detected peaks.
    public static func compute(
        times: [Double],
        values: [Double],
        signal: Signal,
        minPeriod: Double = 12,
        maxPeriod: Double = 720,
        numFreqs: Int = 500
    ) -> PeriodogramResult

    // MARK: - Convenience

    /// Extract a named signal from records and compute periodogram.
    ///
    /// - Parameters:
    ///   - records: Sleep records (≥14 required, returns empty result otherwise).
    ///   - signal: Which signal to analyze.
    ///   - healthProfiles: Required for .restingHR and .nocturnalHRV signals.
    /// - Returns: Periodogram result. Empty if insufficient data.
    public static func analyze(
        _ records: [SleepRecord],
        signal: Signal,
        healthProfiles: [DayHealthProfile] = []
    ) -> PeriodogramResult

    /// Analyze all available signals at once.
    /// Skips .restingHR and .nocturnalHRV if healthProfiles lack data.
    public static func analyzeAll(
        _ records: [SleepRecord],
        healthProfiles: [DayHealthProfile] = []
    ) -> [Signal: PeriodogramResult]
}
```

#### Algorithm (from research document §4)

For each candidate frequency ω = 2π/period:

1. Compute phase offset τ to normalize: `τ = atan2(Σ sin(2ωt), Σ cos(2ωt)) / (2ω)`
2. Fit sinusoid — measure variance explained:
   ```
   P(ω) = 1/(2σ²) × [ (Σ yᵢ cos(ω(tᵢ-τ)))² / Σ cos²(ω(tᵢ-τ))
                      + (Σ yᵢ sin(ω(tᵢ-τ)))² / Σ sin²(ω(tᵢ-τ)) ]
   ```
3. Values are mean-centered before computation.

**Frequency grid:** Linearly spaced in **period** (not frequency), so that longer periods get proportionally more resolution. This matches the log-scale X-axis of the chart and avoids over-sampling at short periods. `periods[i] = minPeriod + i × (maxPeriod - minPeriod) / numFreqs`, then `frequencies[i] = 1 / periods[i]`.

**Significance threshold:** Bonferroni-corrected for M independent frequencies:
```
threshold = -ln(1 - (1 - 0.01)^(1/M))
```

#### Peak Detection

1. Find local maxima in the power spectrum (power[i] > power[i-1] AND power[i] > power[i+1])
2. Filter to peaks above significance threshold
3. Auto-label peaks near known biological periods using `PeakLabel` enum:
   - 24h ± 2h → `.circadian`
   - 168h ± 12h → `.weekly`
   - 336h ± 24h → `.biweekly`
   - 672h ± 48h → `.menstrual`
   - Others → `nil` (shown as raw period value in UI)
4. Sort by power descending

#### Time Coordinate Extraction

Each signal produces a `(times: [Double], values: [Double])` pair. The time coordinate for all signals is **hours from day 0**: `times[i] = Double(record.day) * 24.0`. This places one sample per day at a consistent spacing, with gaps for missing days handled natively by Lomb-Scargle.

For health profile signals (.restingHR, .nocturnalHRV), days with nil values are omitted entirely from both arrays (irregular sampling).

| Signal | Time | Value |
|--------|------|-------|
| `sleepMidpoint` | `day * 24.0` | Unwrapped midpoint (see below) |
| `sleepDuration` | `day * 24.0` | `sleepDuration` directly |
| `cosinorAmplitude` | `day * 24.0` | `cosinor.amplitude` |
| `restingHR` | `profile.day * 24.0` | `restingHR!` (skip nil) |
| `nocturnalHRV` | `profile.day * 24.0` | `avgNocturnalHRV!` (skip nil) |

#### Sleep Midpoint Extraction (unwrapped)

Sleep midpoint lives on a circular domain (0-24h). Raw values like 23→1→2→0 across days would create false discontinuities that corrupt Lomb-Scargle. The solution is **phase unwrapping**: track cumulative midpoint as a continuous signal.

Step 1 — compute circular midpoint per day:
```swift
let rawMid = (bedtimeHour + wakeupHour) / 2
let midpoint = wakeupHour < bedtimeHour ? rawMid + 12 : rawMid
let normalized = midpoint.truncatingRemainder(dividingBy: 24)
```

Step 2 — unwrap the series to be continuous:
```swift
var unwrapped = [midpoints[0]]
for i in 1..<midpoints.count {
    var delta = midpoints[i] - midpoints[i-1]
    if delta > 12 { delta -= 24 }
    if delta < -12 { delta += 24 }
    unwrapped.append(unwrapped[i-1] + delta)
}
```

The unwrapped series preserves true drift direction (e.g., 23→1 becomes 23→25, a +2h shift). Lomb-Scargle then correctly detects the periodicity of this drift.

#### Edge Cases

- **< 14 records:** Return empty PeriodogramResult (no frequencies, no peaks). The convenience method checks this.
- **All values identical:** Variance = 0, return empty Result (flat signal has no periodicity).
- **Nil health values:** For .restingHR and .nocturnalHRV, skip days where the value is nil. If < 14 non-nil values remain, return empty Result.
- **numFreqs = 0 or minPeriod ≥ maxPeriod:** Return empty PeriodogramResult.

### Component 2: Periodogram Panel (UI)

**File:** `spiral journey project/Views/Charts/PeriodogramView.swift`

**Location:** New section within the Analysis tab, below existing charts. Lives in `Views/Charts/` alongside `SlidingCosinorView.swift`, `HRVTrendView.swift`, etc.

#### Layout

```
┌─────────────────────────────────────┐
│  Ritmos Detectados                  │
│                                     │
│  [Midpoint ▾]  ← Signal picker     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Power   Swift Chart        │    │
│  │  │    ╱╲                    │    │
│  │  │   ╱  ╲    ╱╲            │    │
│  │  │──╱────╲──╱──╲─── threshold    │
│  │  │╱       ╲╱    ╲─────     │    │
│  │  └──────────────────────┘    │
│  │  12h    24h   7d   14d  28d  │    │
│  └─────────────────────────────┘    │
│                                     │
│  Picos significativos:              │
│  ● Circadiano — 24.0h  ████████ 0.82│
│  ● Semanal — 7.0d      █████   0.45│
│                                     │
│  ⓘ "Tu sueño tiene un ritmo        │
│     semanal fuerte..."              │
└─────────────────────────────────────┘
```

#### Components

1. **Signal Picker** — `Picker` with `.menu` style. Shows localized signal names. HR and HRV options only appear when `healthProfiles` contain data for those signals. Default selection: `.sleepMidpoint`.

2. **Periodogram Chart** — Swift Charts:
   - `AreaMark` for the power spectrum (filled, semi-transparent)
   - `RuleMark` horizontal dashed line for significance threshold
   - `PointMark` on significant peaks
   - X-axis: period in log scale (12h → 30d), labeled with human units ("24h", "7d", "28d")
   - Y-axis: normalized power (0 to max)

3. **Peak List** — Below chart. Each significant peak shows:
   - Colored dot (matching chart annotation)
   - Label + period ("Circadiano — 24.0h" or "7.0 días" for unlabeled)
   - Horizontal bar proportional to power
   - Power value

4. **Insight Text** — Deterministic rule-based sentence for the strongest peak of the selected signal. Examples:
   - Midpoint + 24h peak strong: "Tu ritmo circadiano es estable a 24.0h — bien sincronizado."
   - Duration + 7d peak: "Tu duración de sueño varía con un ciclo semanal — probablemente por diferencias entre semana y fines de semana."
   - Duration + 28d peak + menstrual data (≥3 profiles where `menstrualFlow != nil && menstrualFlow! > 0`): "Se detecta un ciclo de ~28 días en tu duración de sueño, posiblemente relacionado con tu ciclo menstrual."
   - Duration + 28d peak without menstrual data: "Se detecta un ciclo de ~28 días en tu duración de sueño."
   - No significant peaks: "No se detectan ritmos significativos en esta señal. Esto puede indicar irregularidad o datos insuficientes."

5. **Insufficient data state** — When < 14 records: show message "Necesitas al menos 2 semanas de datos para detectar ritmos" with a progress indicator (X/14 días).

#### Localization

All strings via `Localizable.xcstrings` with keys for all 9 app languages:
- `system`, `en`, `es`, `ca`, `de`, `fr`, `zh`, `ja`, `ar`

Keys include:
- `periodogram.title` — "Ritmos Detectados" / "Detected Rhythms" / ...
- `periodogram.signal.*` — Signal picker labels
- `periodogram.peak.*` — Peak type labels (circadian, weekly, biweekly, menstrual)
- `periodogram.insight.*` — Insight text templates
- `periodogram.insufficientData` — Minimum data message
- `periodogram.noPeaks` — No significant peaks message
- `periodogram.threshold` — "Umbral de significancia" / "Significance threshold"

### Component 3: Integration with SpiralStore

**Storage:**
```swift
// In AnalysisResult
public var periodograms: [LombScargle.Signal: LombScargle.PeriodogramResult] = [:]
```

**Computation trigger:** Inside `SpiralStore.recompute()`. The `recompute()` method dispatches work in a `Task.detached`. The `healthProfiles` property must be captured as a local before entering the detached task (alongside existing captures like `prevStats`, `currentStreak`, etc.):

```swift
// Inside recompute(), before Task.detached:
let hp = healthProfiles

// Inside the detached task, after existing analysis:
if recs.count >= 14 {
    let periodograms = LombScargle.analyzeAll(recs, healthProfiles: hp)
    // Assign inside MainActor.run along with other results
    analysis.periodograms = periodograms
}
```

**Performance:** O(N × M) where N = number of data points (~60-90), M = frequency bins (500). ≈ 45,000 multiply-add operations. Runs in < 1ms on any modern device. No background thread needed.

**Caching:** Results cached in `analysis.periodograms`. Signal picker switches read from cache — no recomputation on UI interaction.

**Conditional signals:** `analyzeAll` checks:
- `.restingHR`: skipped if `healthProfiles.compactMap(\.restingHR).count < 14`
- `.nocturnalHRV`: skipped if `healthProfiles.compactMap(\.avgNocturnalHRV).count < 14`

## What's NOT in Scope

| Item | Why deferred |
|------|-------------|
| τ→spiral mapping | YAGNI — most users entrained to 24h. Can add later if Non-24 detection becomes valuable. |
| Interactive period reconfiguration | Depends on τ→spiral mapping. |
| SpiralDistance metric | Already implemented in `SpiralKit/Sources/SpiralKit/Analysis/SpiralDistance.swift`. |
| Cross-signal correlation | Fase C territory. |
| Foundation Models insights | Deterministic rules sufficient for periodogram interpretation. |

## Testing Strategy

**SpiralKit unit tests** (`LombScargleTests.swift`):
- Pure 24h sinusoid → dominant peak at 24h, significant
- 24h + 168h composite → two peaks detected
- Flat signal (all same value) → no peaks
- < 14 data points → empty result
- Known period with noise → peak within ±2h tolerance
- Sleep midpoint extraction handles midnight wrap (bedtime 23, wake 7 → midpoint 3)
- Sleep midpoint unwrapping handles drift across midnight (23→1→2→0 becomes continuous 23→25→26→24)
- All Signal cases extract valid (times, values) arrays
- Deterministic: same input → same output

**UI verification** (manual, on device):
- Picker shows only available signals (HR/HRV hidden without Watch data)
- Chart renders with correct axes (log scale X, linear Y)
- Peaks annotated on chart match peak list below
- Insight text matches strongest peak
- < 14 days shows insufficient data message
- All 9 languages render correctly

## References

- Lomb, N.R. (1976). Least-squares frequency analysis of unequally spaced data. *Astrophysics and Space Science*, 39, 447-462.
- Scargle, J.D. (1982). Studies in astronomical time series analysis. *The Astrophysical Journal*, 263, 835-853.
- Research document §4: "Periodograma Lomb-Scargle"
- Research document §10: "Métrica de Distancia Espiral" (already implemented)
