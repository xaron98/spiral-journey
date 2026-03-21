# DNA Insights Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign DNAInsightsView from flat identical cards into a Story Flow layout with visual hierarchy, human language, progressive disclosure, and actionable insights.

**Architecture:** View-layer redesign with one minor SpiralKit change (expose threshold constants). Sections are rewritten individually, orchestrated by a modified DNAInsightsView. Shared components (ExpandableCard, StrengthDotsView, etc.) are built first, then consumed by sections.

**Tech Stack:** SwiftUI, RealityKit (iOS 18+), SpiralKit, SwiftData, Canvas API

**Spec:** `docs/superpowers/specs/2026-03-21-dna-insights-redesign.md`

**Build command:** `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

**SpiralKit test command:** `cd SpiralKit && swift test --filter HealthMarkerTests`

---

## Chunk 1: Foundation — SpiralKit Change + Shared Components

### Task 1: Extract HealthMarkerDetector threshold constants

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HealthMarkerDetector.swift`
- Test: `SpiralKit/Tests/SpiralKitTests/SleepDNA/HealthMarkerTests.swift`

- [ ] **Step 1: Add public static threshold constants**

In `HealthMarkerDetector.swift`, add these constants at the top of the `public enum`:

```swift
// Alert thresholds — used by HealthInsightRules for proximity warnings
public static let circadianCoherenceThreshold = 0.2
public static let fragmentationScoreThreshold = 0.6
public static let driftSeverityThreshold = 15.0
public static let homeostasisBalanceThreshold = 0.3
```

- [ ] **Step 2: Replace inline literals with constants**

Replace the 4 inline threshold values at lines ~87, ~94, ~101, ~108 with the new constants:
- `coherence < 0.2` → `coherence < Self.circadianCoherenceThreshold`
- `fragmentation > 0.6` → `fragmentation > Self.fragmentationScoreThreshold`
- `drift > 15` → `drift > Self.driftSeverityThreshold`
- `hb > 0.3` → `hb > Self.homeostasisBalanceThreshold`

- [ ] **Step 3: Run existing HealthMarker tests**

Run: `cd SpiralKit && swift test --filter HealthMarkerTests`
Expected: All tests pass (behavior unchanged, just extracted constants)

- [ ] **Step 4: Commit**

```bash
git add SpiralKit/Sources/SpiralKit/Analysis/SleepDNA/HealthMarkerDetector.swift
git commit -m "refactor: extract HealthMarkerDetector thresholds as public constants"
```

---

### Task 2: Create ExpandableCard shared component

**Files:**
- Create: `spiral journey project/Views/DNA/Components/ExpandableCard.swift`

- [ ] **Step 1: Create the Components directory and ExpandableCard**

```swift
import SwiftUI

/// Reusable collapsible card with liquid glass background.
/// Collapsed content always visible; detail content revealed on tap.
struct ExpandableCard<Summary: View, Detail: View>: View {

    @Binding var isExpanded: Bool
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(spacing: 0) {
            summary()

            if isExpanded {
                detail()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Components/ExpandableCard.swift"
git commit -m "feat: add ExpandableCard shared component for progressive disclosure"
```

---

### Task 3: Create StrengthDotsView shared component

**Files:**
- Create: `spiral journey project/Views/DNA/Components/StrengthDotsView.swift`

- [ ] **Step 1: Create StrengthDotsView**

```swift
import SwiftUI

/// Displays filled/empty dots to indicate strength level (e.g., PLV strength).
struct StrengthDotsView: View {
    let level: Int      // number of filled dots
    let maxLevel: Int   // total dots
    var color: Color = SpiralColors.accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<maxLevel, id: \.self) { i in
                Circle()
                    .fill(i < level ? color : color.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Components/StrengthDotsView.swift"
git commit -m "feat: add StrengthDotsView component for visual strength indicators"
```

---

### Task 4: Create MotifHeatmapBar component

**Files:**
- Create: `spiral journey project/Views/DNA/Components/MotifHeatmapBar.swift`

- [ ] **Step 1: Create MotifHeatmapBar**

Canvas-drawn row of colored blocks. Each block = 1 week, color = motif assignment.

```swift
import SwiftUI
import SpiralKit

/// Mini heatmap showing weekly motif assignments as colored blocks.
struct MotifHeatmapBar: View {
    /// Motif index per week (-1 = no motif assigned).
    let weekMotifIndices: [Int]
    /// Color for each motif index.
    let motifColors: [Int: Color]
    /// Default color for unassigned weeks.
    var defaultColor: Color = SpiralColors.surface

    var body: some View {
        Canvas { context, size in
            let count = max(1, weekMotifIndices.count)
            let blockW = size.width / CGFloat(count)
            let gap: CGFloat = 2
            let h = size.height

            for (i, motifIdx) in weekMotifIndices.enumerated() {
                let color = motifColors[motifIdx] ?? defaultColor
                let rect = CGRect(
                    x: CGFloat(i) * blockW + gap / 2,
                    y: 0,
                    width: max(1, blockW - gap),
                    height: h
                )
                let path = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(path, with: .color(color))
            }
        }
        .frame(height: 12)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Components/MotifHeatmapBar.swift"
git commit -m "feat: add MotifHeatmapBar Canvas component for weekly pattern visualization"
```

---

### Task 5: Create SimilaritySparkline component

**Files:**
- Create: `spiral journey project/Views/DNA/Components/SimilaritySparkline.swift`

- [ ] **Step 1: Create SimilaritySparkline**

```swift
import SwiftUI

/// Mini line chart showing recent similarity scores as a sparkline.
struct SimilaritySparkline: View {
    let values: [Double]  // similarity values [0,1]
    var lineColor: Color = SpiralColors.accent
    var height: CGFloat = 30

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let minV = max(0, (values.min() ?? 0) - 0.1)
            let maxV = min(1, (values.max() ?? 1) + 0.1)
            let range = max(0.01, maxV - minV)

            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((v - minV) / range))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(lineColor), lineWidth: 2)

            // Dot on last value
            if let last = values.last {
                let x = size.width
                let y = size.height * (1 - CGFloat((last - minV) / range))
                let dot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(lineColor))
            }
        }
        .frame(height: height)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Components/SimilaritySparkline.swift"
git commit -m "feat: add SimilaritySparkline Canvas component for trend visualization"
```

---

## Chunk 2: Helper Modules

### Task 6: Create HealthInsightRules

**Files:**
- Create: `spiral journey project/Views/DNA/Helpers/HealthInsightRules.swift`

- [ ] **Step 1: Create the Helpers directory and HealthInsightRules**

Maps alert types to actionable Spanish/English text. Also provides proximity warnings.

```swift
import Foundation
import SpiralKit

/// Deterministic mapping from health alert/marker state to actionable text.
struct HealthInsightRules {

    /// Actionable insight for a triggered alert.
    static func insight(for alertType: AlertType, bundle: Bundle) -> String {
        let key: String
        switch alertType {
        case .circadianAnarchy:  key = "dna.health.insight.anarchy"
        case .highFragmentation: key = "dna.health.insight.fragmentation"
        case .severeDrift:       key = "dna.health.insight.drift"
        case .highDesynchrony:   key = "dna.health.insight.desync"
        default:                 return ""
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    /// Proximity warning when a marker is within 20% of its threshold.
    /// Returns nil if marker is not near any threshold.
    static func proximityWarning(
        markers: HealthMarkers,
        bundle: Bundle
    ) -> [(marker: String, text: String)] {
        var warnings: [(String, String)] = []

        let coherenceThresh = HealthMarkerDetector.circadianCoherenceThreshold
        let fragThresh = HealthMarkerDetector.fragmentationScoreThreshold
        let driftThresh = HealthMarkerDetector.driftSeverityThreshold
        let hbThresh = HealthMarkerDetector.homeostasisBalanceThreshold

        // Coherence: alert triggers when BELOW threshold, so "near" = slightly above
        if markers.circadianCoherence >= coherenceThresh &&
           markers.circadianCoherence < coherenceThresh * 1.2 {
            warnings.append(("coherence", NSLocalizedString("dna.health.proximity.coherence", bundle: bundle, comment: "")))
        }

        // Fragmentation: alert triggers when ABOVE threshold
        if markers.fragmentationScore <= fragThresh &&
           markers.fragmentationScore > fragThresh * 0.8 {
            warnings.append(("fragmentation", NSLocalizedString("dna.health.proximity.fragmentation", bundle: bundle, comment: "")))
        }

        // Drift: alert triggers when ABOVE threshold
        if markers.driftSeverity <= driftThresh &&
           markers.driftSeverity > driftThresh * 0.8 {
            warnings.append(("drift", NSLocalizedString("dna.health.proximity.drift", bundle: bundle, comment: "")))
        }

        // HB: alert triggers when ABOVE threshold
        if markers.homeostasisBalance <= hbThresh &&
           markers.homeostasisBalance > hbThresh * 0.8 {
            warnings.append(("hb", NSLocalizedString("dna.health.proximity.hb", bundle: bundle, comment: "")))
        }

        return warnings
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Helpers/HealthInsightRules.swift"
git commit -m "feat: add HealthInsightRules for actionable health insights"
```

---

### Task 7: Create BasePairDescriptor

**Files:**
- Create: `spiral journey project/Views/DNA/Helpers/BasePairDescriptor.swift`

- [ ] **Step 1: Create BasePairDescriptor**

Translates raw PLV synchrony data into human-readable cause-effect phrases.

```swift
import Foundation
import SpiralKit

/// Translates BasePairSynchrony + ExpressionRule into human-readable phrases.
struct BasePairDescriptor {

    struct Description {
        let phrase: String      // "El café influye fuertemente en tu hora de dormir"
        let strengthLevel: Int  // 1=weak, 2=moderate, 3=strong
        let tip: String?        // Actionable insight from ExpressionRule (optional)
    }

    /// Feature index → localization key for context features (strand 2).
    private static let contextKeys: [Int: String] = [
        8: "dna.basepair.caffeine", 9: "dna.basepair.exercise",
        10: "dna.basepair.alcohol", 11: "dna.basepair.melatonin",
        12: "dna.basepair.stress", 13: "dna.basepair.weekend",
        14: "dna.basepair.hourlyDrift", 15: "dna.basepair.sleepQuality"
    ]

    /// Feature index → localization key for sleep features (strand 1).
    private static let sleepKeys: [Int: String] = [
        0: "dna.basepair.bedtime", 1: "dna.basepair.wakeTime",
        2: "dna.basepair.duration", 3: "dna.basepair.latency",
        4: "dna.basepair.deepSleep", 5: "dna.basepair.rem",
        6: "dna.basepair.fragmentation", 7: "dna.basepair.efficiency"
    ]

    static func describe(
        _ pair: BasePairSynchrony,
        rule: ExpressionRule?,
        bundle: Bundle
    ) -> Description {
        let contextName = loc(contextKeys[pair.contextFeatureIndex] ?? "dna.basepair.factor", bundle)
        let sleepName = loc(sleepKeys[pair.sleepFeatureIndex] ?? "dna.basepair.sleep", bundle)

        let strengthLevel: Int
        let strengthWord: String
        if pair.plv > 0.7 {
            strengthLevel = 3
            strengthWord = loc("dna.basepair.phrase.strongly", bundle)
        } else if pair.plv >= 0.4 {
            strengthLevel = 2
            strengthWord = loc("dna.basepair.phrase.moderately", bundle)
        } else {
            strengthLevel = 1
            strengthWord = loc("dna.basepair.phrase.slightly", bundle)
        }

        // "El café influye fuertemente en tu hora de dormir"
        let phrase = String(
            format: loc("dna.basepair.phrase.template", bundle),
            contextName, strengthWord, sleepName
        )

        // Actionable tip from expression rule
        var tip: String? = nil
        if let rule = rule {
            let delta = abs(rule.qualityWith - rule.qualityWithout)
            if delta > 0.05 {
                let betterWhen = rule.qualityWith > rule.qualityWithout
                    ? loc("dna.basepair.phrase.tip.with", bundle)
                    : loc("dna.basepair.phrase.tip.without", bundle)
                tip = String(format: betterWhen, contextName)
            }
        }

        return Description(phrase: phrase, strengthLevel: strengthLevel, tip: tip)
    }

    private static func loc(_ key: String, _ bundle: Bundle) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/Helpers/BasePairDescriptor.swift"
git commit -m "feat: add BasePairDescriptor for human-readable sleep connection phrases"
```

---

## Chunk 3: Hero Card + Helix Modifications

### Task 8: Create DNAHeroCard (replaces DNAStateSection)

**Files:**
- Create: `spiral journey project/Views/DNA/DNAHeroCard.swift`
- Reference: `spiral journey project/Views/DNA/DNAStateSection.swift` (will be deleted in Task 14)

- [ ] **Step 1: Create DNAHeroCard**

The hero card combines circadian state + tonight's prediction + trend. Tap expands to show technical values.

Key data sources:
- `profile.healthMarkers.circadianCoherence` → state label + color
- `profile.prediction` → bedtime/wake (from `SequencePrediction`)
- `previousProfile?.healthMarkers.circadianCoherence` → trend calculation

The view receives `previousProfile: SleepDNAProfile?` from the parent `DNAInsightsView`.

```swift
import SwiftUI
import SpiralKit

/// Hero card: circadian state + prediction + trend. Largest visual element.
struct DNAHeroCard: View {

    let profile: SleepDNAProfile
    let previousProfile: SleepDNAProfile?

    @Environment(\.languageBundle) private var bundle
    @State private var isExpanded = false

    // MARK: - Computed

    private var coherence: Double { profile.healthMarkers.circadianCoherence }
    private var hb: Double { profile.healthMarkers.homeostasisBalance }

    private var stateLabel: String {
        if coherence > 0.7 { return loc("dna.state.synchronized") }
        if coherence >= 0.4 { return loc("dna.state.transitioning") }
        return loc("dna.state.misaligned")
    }

    private var stateColor: Color {
        if coherence > 0.7 { return SpiralColors.good }
        if coherence >= 0.4 { return SpiralColors.awakeSleep }
        return SpiralColors.poor
    }

    private enum Trend { case improving, stable, declining, unknown }

    private var trend: Trend {
        guard let prev = previousProfile else { return .unknown }
        let delta = coherence - prev.healthMarkers.circadianCoherence
        if delta > 0.05 { return .improving }
        if delta < -0.05 { return .declining }
        return .stable
    }

    // MARK: - Body

    var body: some View {
        ExpandableCard(isExpanded: $isExpanded) {
            summaryContent
        } detail: {
            detailContent
        }
    }

    // MARK: - Summary (always visible)

    @ViewBuilder
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // State header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(SpiralColors.accent)
                Text(loc("dna.state.header"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
                trendBadge
            }

            // State word
            Text(stateLabel)
                .font(.title.bold())
                .fontDesign(.rounded)
                .foregroundStyle(stateColor)

            // Prediction
            if let pred = profile.prediction {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(SpiralColors.accent)
                    Text("\(loc("dna.hero.sleep")) \(formatHour(pred.predictedBedtime))  →  \(loc("dna.hero.wake")) \(formatHour(pred.predictedWake))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SpiralColors.text)
                }

                // Confidence bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(SpiralColors.surface)
                            .frame(height: 4)
                        Capsule()
                            .fill(SpiralColors.accent.opacity(0.6))
                            .frame(width: geo.size.width * pred.confidence, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - Detail (expanded)

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(SpiralColors.border)
                .padding(.top, 8)

            detailRow(loc("dna.state.coherence"), "\(Int(coherence * 100))%")
            detailRow("HB", String(format: "%.2f", hb))

            if let has = profile.hasScore {
                detailRow("HAS", String(format: "%.0f%%", has * 100))
            }

            if let pred = profile.prediction {
                detailRow(loc("dna.hero.confidence"), "\(Int(pred.confidence * 100))%")
                detailRow(loc("dna.hero.basedOn"), "\(pred.basedOnWeekIndices.count) \(loc("dna.motif.weeks"))")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var trendBadge: some View {
        switch trend {
        case .improving:
            Label(loc("dna.hero.trend.improving"), systemImage: "arrow.up.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.good)
        case .declining:
            Label(loc("dna.hero.trend.declining"), systemImage: "arrow.down.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.poor)
        case .stable:
            Label(loc("dna.hero.trend.stable"), systemImage: "arrow.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.muted)
        case .unknown:
            EmptyView()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
            Text(value)
                .font(.footnote.weight(.medium).monospaced())
                .foregroundStyle(SpiralColors.text)
        }
    }

    // MARK: - Helpers

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h) % 24
        let min  = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hour, min)
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (DNAHeroCard exists but isn't wired into DNAInsightsView yet)

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNAHeroCard.swift"
git commit -m "feat: add DNAHeroCard with state, prediction, and trend"
```

---

### Task 9: Modify HelixRealityView — tier overlay + callback

**Files:**
- Modify: `spiral journey project/Views/DNA/HelixRealityView.swift`

- [ ] **Step 1: Add onWeekTapped callback and tier overlay**

Changes to `HelixRealityView.swift`:

1. Add `onWeekTapped` parameter and tier overlay property:
```swift
var onWeekTapped: ((Int) -> Void)? = nil
```

2. In the `overlays` computed property, add a bottom tier overlay (above the existing week info card):
```swift
// Bottom-left: tier + weeks badge
HStack(spacing: 6) {
    Text("\(profile.helixGeometry.count / 7) \(loc("dna.tier.weeksOfData"))")
        .font(.caption2)
        .foregroundStyle(SpiralColors.muted)
    Text("·")
        .foregroundStyle(SpiralColors.subtle)
    Text(tierLabel)
        .font(.caption2.weight(.medium))
        .foregroundStyle(tierColor)
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
.background(Capsule().fill(SpiralColors.surface.opacity(0.7)))
.padding(.leading, 12)
.padding(.bottom, 12)
```

Add tier helpers (logic from DNATierSection, which will be deleted in Task 16):
```swift
private var tierLabel: String {
    switch profile.tier {
    case .basic:        return loc("dna.tier.basic")
    case .intermediate: return loc("dna.tier.intermediate")
    case .full:         return loc("dna.tier.full")
    }
}

private var tierColor: Color {
    switch profile.tier {
    case .basic:        return SpiralColors.subtle
    case .intermediate: return SpiralColors.accent
    case .full:         return SpiralColors.good
    }
}
```

Note: `profile.tier` is an `AnalysisTier` enum — access it directly, not via string conversion.

3. In `tapGesture.onEnded`, add the callback:
```swift
onWeekTapped?(clampedWeek)
```

4. Remove `clipShape(RoundedRectangle(...))` from the main ZStack — the helix should float on the page background.

5. Remove `SpiralColors.bg` background from the ZStack — let the parent background show through.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/HelixRealityView.swift"
git commit -m "feat: add tier overlay and onWeekTapped callback to HelixRealityView"
```

---

## Chunk 4: Section Rewrites

### Task 10: Rewrite DNAHealthSection

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAHealthSection.swift`

- [ ] **Step 1: Rewrite with collapsed/expanded, proximity, and insights**

Complete rewrite of `DNAHealthSection.swift`:

```swift
import SwiftUI
import SpiralKit

/// "Tu salud circadiana" — health alerts with gradient severity, proximity warnings, and actionable insights.
struct DNAHealthSection: View {

    let profile: SleepDNAProfile
    let previousProfile: SleepDNAProfile?

    @Environment(\.languageBundle) private var bundle
    @State private var isExpanded = false

    private var markers: HealthMarkers { profile.healthMarkers }
    private var alerts: [HealthAlert] { markers.alerts }
    private var hasUrgent: Bool { alerts.contains { $0.severity == .urgent } }
    private var allGood: Bool { alerts.isEmpty }

    var body: some View {
        ExpandableCard(isExpanded: $isExpanded) {
            summaryContent
        } detail: {
            detailContent
        }
        .onAppear {
            // Auto-expand for urgent alerts
            if hasUrgent { isExpanded = true }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Image(systemName: "heart.text.clipboard")
                    .foregroundStyle(SpiralColors.accent)
                Text(loc("dna.health.header"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            if allGood {
                // Stable — single green line
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(SpiralColors.good)
                    Text(loc("dna.health.stable"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SpiralColors.good)
                }
                // Show proximity warnings if near thresholds
                let warnings = HealthInsightRules.proximityWarning(markers: markers, bundle: bundle)
                if !warnings.isEmpty {
                    ForEach(warnings, id: \.marker) { warning in
                        Text(warning.text)
                            .font(.caption)
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            } else if hasUrgent {
                // Urgent — red, auto-expanded
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(SpiralColors.poor)
                    Text(String(format: loc("dna.health.collapsed.alert"), alerts.count))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SpiralColors.poor)
                }
            } else {
                // Caution — amber
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SpiralColors.awakeSleep)
                    Text(String(format: loc("dna.health.collapsed.caution"), alerts.count))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SpiralColors.awakeSleep)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(SpiralColors.border)
                .padding(.top, 8)

            ForEach(alerts) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: alertIcon(alert.severity))
                            .font(.body)
                            .foregroundStyle(alertColor(alert.severity))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizedMessage(for: alert))
                                .font(.footnote)
                                .foregroundStyle(SpiralColors.text)

                            // Persistence context
                            Text(persistenceLabel(for: alert))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.subtle)

                            // Actionable insight
                            let insight = HealthInsightRules.insight(for: alert.type, bundle: bundle)
                            if !insight.isEmpty {
                                Text(insight)
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.accent)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func persistenceLabel(for alert: HealthAlert) -> String {
        // Check if the same alert type existed in the previous profile
        guard let prev = previousProfile else {
            return loc("dna.health.persistence.new")
        }
        let prevHadSame = prev.healthMarkers.alerts.contains { $0.type == alert.type }
        if prevHadSame {
            // Persistent — show "week N" (simplified: we know it's at least 2nd week)
            return String(format: loc("dna.health.persistence.weeks"), 2)
        }
        return loc("dna.health.persistence.new")
    }

    private func localizedMessage(for alert: HealthAlert) -> String {
        switch alert.type {
        case .circadianAnarchy:  return loc("dna.health.alert.anarchy")
        case .highFragmentation: return loc("dna.health.alert.fragmentation")
        case .severeDrift:       return loc("dna.health.alert.drift")
        case .highDesynchrony:   return loc("dna.health.alert.desync")
        case .remDriftAbnormal:  return loc("dna.health.alert.rem")
        case .novelPattern:      return loc("dna.health.alert.novel")
        }
    }

    private func alertIcon(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .urgent:  return "exclamationmark.octagon.fill"
        }
    }

    private func alertColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .info:    return SpiralColors.accent
        case .warning: return SpiralColors.awakeSleep
        case .urgent:  return SpiralColors.poor
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNAHealthSection.swift"
git commit -m "feat: rewrite DNAHealthSection with progressive disclosure and insights"
```

---

### Task 11: Rewrite DNAMotifSection

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAMotifSection.swift`

- [ ] **Step 1: Rewrite with human language, heatmap, and expandable detail**

Complete rewrite of `DNAMotifSection.swift`. Key changes:
- Use `ExpandableCard` for collapse/expand
- Collapsed: natural language description of dominant motif + mutation context phrase + `MotifHeatmapBar`
- Expanded: all motifs with stats, mutation history
- Learning state: progress bar + motivational text ("En X semanas más descubriremos tus patrones")
- Use `SleepMutation.motifID` to look up parent motif name for context phrases:
```swift
// Look up motif name from mutation
let motifName: String? = profile.motifs
    .first(where: { $0.id == mutation.motifID })
    .map { localizedMotifName($0.name) }
```

Build motif-to-week-index mapping for `MotifHeatmapBar`:
```swift
// Build week → motif index mapping
var weekMotifs: [Int] = Array(repeating: -1, count: totalWeeks)
for (mIdx, motif) in profile.motifs.enumerated() {
    for weekIdx in motif.instanceWeekIndices {
        if weekIdx < totalWeeks { weekMotifs[weekIdx] = mIdx }
    }
}
```

Assign colors to motifs using a small palette:
```swift
let motifPalette: [Color] = [SpiralColors.accent, SpiralColors.good, SpiralColors.awakeSleep, SpiralColors.moderate]
var colorMap: [Int: Color] = [:]
for (i, _) in profile.motifs.enumerated() {
    colorMap[i] = motifPalette[i % motifPalette.count]
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNAMotifSection.swift"
git commit -m "feat: rewrite DNAMotifSection with human language and heatmap"
```

---

### Task 12: Rewrite DNABasePairsSection

**Files:**
- Modify: `spiral journey project/Views/DNA/DNABasePairsSection.swift`

- [ ] **Step 1: Rewrite with cause-effect phrases and strength dots**

Complete rewrite of `DNABasePairsSection.swift`. Key changes:
- Use `ExpandableCard` for collapse/expand
- Collapsed: top 3 connections as `BasePairDescriptor.describe()` phrases + `StrengthDotsView` + optional tip
- Expanded: all pairs with raw PLV, phase diff, feature indices
- Match each `BasePairSynchrony` to its `ExpressionRule` (if any) by matching `contextFeatureIndex`
- Still hidden in tier `.basic`
- Use `enumerated()` with `id: \.offset` for ForEach (BasePairSynchrony lacks Identifiable)

```swift
// Match expression rules to base pairs
let rulesForPair: ExpressionRule? = profile.expressionRules.first(where: {
    $0.regulatorFeatureIndex == pair.contextFeatureIndex
})
let desc = BasePairDescriptor.describe(pair, rule: rulesForPair, bundle: bundle)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNABasePairsSection.swift"
git commit -m "feat: rewrite DNABasePairsSection with human-readable connection phrases"
```

---

### Task 13: Rewrite DNAAlignmentSection

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAAlignmentSection.swift`

- [ ] **Step 1: Rewrite — remove prediction, add sparkline and date context**

Complete rewrite of `DNAAlignmentSection.swift`. Key changes:
- Remove prediction display (moved to Hero Card)
- Use `ExpandableCard` for collapse/expand
- Collapsed: contextual phrase with date range ("Esta semana se parece un 78% a la semana del 3 de febrero") + `SimilaritySparkline`
- Expanded: ranked list of similar weeks with similarity %
- Only visible in tier `.intermediate` or `.full`; show placeholder in `.basic`

Week index → date range conversion:
```swift
private func weekDateRange(_ weekIndex: Int) -> String {
    let startDay = weekIndex * 7
    guard startDay < profile.nucleotides.count else { return "" }
    // Each nucleotide represents one day from the start of data collection
    // Use profile.computedAt and work backwards
    let totalDays = profile.nucleotides.count
    let daysAgo = totalDays - startDay
    let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: profile.computedAt) ?? profile.computedAt
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM"
    return formatter.string(from: startDate)
}
```

Sparkline data: extract similarity values from recent alignments sorted by week index.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNAAlignmentSection.swift"
git commit -m "feat: rewrite DNAAlignmentSection with sparkline and date context"
```

---

## Chunk 5: Orchestrator, Localization, and Cleanup

### Task 14: Rewrite DNAInsightsView orchestrator

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAInsightsView.swift`

- [ ] **Step 1: Add previous snapshot fetching and scroll-to coordination**

Key changes to `DNAInsightsView.swift`:

1. Add state for previous profile:
```swift
@State private var previousProfile: SleepDNAProfile?
```

2. In the existing `.task {}` block (which already calls `dnaService.refreshIfNeeded`), add the previous snapshot fetch:
```swift
// Fetch the previous snapshot (not today's)
let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())
var descriptor = FetchDescriptor<SDSleepDNASnapshot>(
    predicate: #Predicate { $0.computedAt < today },
    sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
)
descriptor.fetchLimit = 1
if let snapshot = try? modelContext.fetch(descriptor).first,
   let json = snapshot.profileJSON {
    previousProfile = try? JSONDecoder().decode(SleepDNAProfile.self, from: json)
}
```
Note: `var descriptor` (not `let`) because `FetchDescriptor` is a struct and `fetchLimit` is a mutable property.

3. Wrap `profileContent` in `ScrollViewReader` and preserve `.scrollDisabled(isInteractingWith3D)`:
```swift
ScrollViewReader { proxy in
    ScrollView(showsIndicators: false) {
        VStack(spacing: 16) {
            // sections with .id() anchors
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }
    .scrollDisabled(isInteractingWith3D) // PRESERVE: prevents scroll interference during 3D helix gestures
}
```

4. Update section order — preserve questionnaire banner, pass `previousProfile`:
```swift
// Weekly check-in banner (existing feature — preserve)
if questionnaireAvailable {
    questionnaireBanner
}

// 1. Hero Card
DNAHeroCard(profile: profile, previousProfile: previousProfile)

// 2. Helix 3D
if #available(iOS 18.0, *), profile.helixGeometry.count >= 3 {
    HelixRealityView(profile: profile, records: store.records,
                     isInteractingWith3D: $isInteractingWith3D,
                     onWeekTapped: { week in
        // Scroll to patterns section if week belongs to a motif
        if profile.motifs.contains(where: { $0.instanceWeekIndices.contains(week) }) {
            withAnimation { proxy.scrollTo("patterns", anchor: .top) }
        }
    })
}

// 3. Health
DNAHealthSection(profile: profile, previousProfile: previousProfile)

// 4. Patterns
DNAMotifSection(profile: profile)
    .id("patterns")

// 5. Connections
DNABasePairsSection(profile: profile)

// 6. Similarity
DNAAlignmentSection(profile: profile)

// 7. Footer
footerContent(profile)
```

5. Add `footerContent` method — disclaimer + tier motivation:
```swift
@ViewBuilder
private func footerContent(_ profile: SleepDNAProfile) -> some View {
    VStack(spacing: 8) {
        if profile.tier != .full {
            let remaining = 8 - profile.dataWeeks
            if remaining > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(i < profile.dataWeeks ? SpiralColors.accent : SpiralColors.surface)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(String(format: loc("dna.tier.motivation"), profile.dataWeeks, remaining))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .multilineTextAlignment(.center)
            }
        }
        Text(loc("dna.disclaimer"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
}
```

6. Remove `DNAStateSection` and `DNATierSection` from the section list.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Views/DNA/DNAInsightsView.swift"
git commit -m "feat: rewrite DNAInsightsView with Story Flow layout and scroll coordination"
```

---

### Task 15: Add localization keys

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

- [ ] **Step 1: Add all new localization keys**

Add these key categories to `Localizable.xcstrings` (JSON format with `en` and `es` translations):

**Hero card (`dna.hero.*`):**
- `dna.hero.sleep` → en: "Sleep", es: "Dormir"
- `dna.hero.wake` → en: "Wake", es: "Despertar"
- `dna.hero.confidence` → en: "Confidence", es: "Confianza"
- `dna.hero.basedOn` → en: "Based on", es: "Basado en"
- `dna.hero.trend.improving` → en: "improving", es: "mejorando"
- `dna.hero.trend.declining` → en: "declining", es: "empeorando"
- `dna.hero.trend.stable` → en: "stable", es: "estable"

**Health insights (`dna.health.insight.*`):**
- `dna.health.insight.anarchy` → en: "Try to keep regular schedules on weekends", es: "Intenta mantener horarios regulares el fin de semana"
- `dna.health.insight.fragmentation` → en: "Avoid screens 1h before bed", es: "Evita pantallas 1h antes de dormir"
- `dna.health.insight.drift` → en: "Your sleep schedule is shifting — try fixing your wake time", es: "Tu horario de sueño se está desplazando — intenta fijar la hora de despertar"
- `dna.health.insight.desync` → en: "Your internal clock and your schedule are not aligned", es: "Tu reloj interno y tus horarios no están alineados"

**Health proximity (`dna.health.proximity.*`):**
- `dna.health.proximity.coherence` → en: "Coherence: normal (near limit)", es: "Coherencia: normal (cerca del límite)"
- `dna.health.proximity.fragmentation` → en: "Fragmentation: normal (near limit)", es: "Fragmentación: normal (cerca del límite)"
- `dna.health.proximity.drift` → en: "Drift: normal (near limit)", es: "Drift: normal (cerca del límite)"
- `dna.health.proximity.hb` → en: "Balance: normal (near limit)", es: "Balance: normal (cerca del límite)"

**Health collapsed states:**
- `dna.health.collapsed.caution` → en: "%d signal to watch", es: "%d señal a observar"
- `dna.health.collapsed.alert` → en: "%d active alerts", es: "%d alertas activas"
(Note: the stable state reuses the existing `dna.health.stable` key — no new key needed)
- `dna.health.persistence.new` → en: "new this week", es: "nuevo esta semana"
- `dna.health.persistence.weeks` → en: "week %d", es: "semana %d"

**Base pair phrases (`dna.basepair.phrase.*`):**
- `dna.basepair.phrase.template` → en: "%1$@ %2$@ influences your %3$@", es: "%1$@ influye %2$@ en tu %3$@"
- `dna.basepair.phrase.strongly` → en: "strongly", es: "fuertemente"
- `dna.basepair.phrase.moderately` → en: "moderately", es: "moderadamente"
- `dna.basepair.phrase.slightly` → en: "slightly", es: "ligeramente"
- `dna.basepair.phrase.tip.with` → en: "You sleep better on days with %@", es: "Duermes mejor los días con %@"
- `dna.basepair.phrase.tip.without` → en: "You sleep better on days without %@", es: "Duermes mejor los días sin %@"

**Alignment context (`dna.alignment.context.*`):**
- `dna.alignment.context.similar` → en: "This week is %d%% similar to the week of %@", es: "Esta semana se parece un %d%% a la semana del %@"
- `dna.alignment.context.placeholder` → en: "With more data we can detect similar weeks", es: "Con más datos podremos detectar semanas similares"

**Tier motivation (`dna.tier.motivation`):**
- `dna.tier.motivation` → en: "Week %d of 8. In %d more weeks full analysis unlocks.", es: "Semana %d de 8. En %d semanas más se desbloquea el análisis completo."

**Motif descriptions:**
- `dna.motif.description.dominant` → en: "Your most frequent pattern: %1$@ (%2$d of the last %3$d weeks)", es: "Tu patrón más frecuente: %1$@ (%2$d de las últimas %3$d semanas)"
- `dna.motif.description.mutation.better` → en: "This week you slept better than expected for your pattern (%@)", es: "Esta semana dormiste mejor de lo esperado para tu patrón (%@)"
- `dna.motif.description.mutation.worse` → en: "This week you slept worse than expected for your pattern (%@)", es: "Esta semana dormiste peor de lo esperado para tu patrón (%@)"
- `dna.motif.description.learning` → en: "In %d more weeks we'll discover your recurring patterns", es: "En %d semanas más descubriremos tus patrones recurrentes"

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "spiral journey project/Localizable.xcstrings"
git commit -m "feat: add localization keys for DNA Insights redesign (EN/ES)"
```

---

### Task 16: Delete DNATierSection + cleanup DNAStateSection

**Files:**
- Delete: `spiral journey project/Views/DNA/DNATierSection.swift`
- Delete: `spiral journey project/Views/DNA/DNAStateSection.swift` (replaced by DNAHeroCard)

- [ ] **Step 1: Remove files from the Xcode project**

Delete `DNATierSection.swift` — its content is now in the helix overlay + footer.
Delete `DNAStateSection.swift` — replaced by `DNAHeroCard.swift`.

Verify no other files import or reference these views (they were only used in `DNAInsightsView.profileContent`, which was updated in Task 14).

- [ ] **Step 2: Build to verify the project compiles without deleted files**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git rm "spiral journey project/Views/DNA/DNATierSection.swift"
git rm "spiral journey project/Views/DNA/DNAStateSection.swift"
git commit -m "chore: remove DNATierSection and DNAStateSection (replaced by helix overlay and DNAHeroCard)"
```

---

### Task 17: Full build verification

- [ ] **Step 1: Run full iOS build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run SpiralKit tests**

Run: `cd SpiralKit && swift test`
Expected: All tests pass

- [ ] **Step 3: Verify no regressions in HealthMarker tests**

Run: `cd SpiralKit && swift test --filter HealthMarkerTests`
Expected: All tests pass

- [ ] **Step 4: Manual QA checklist**

Open the app in Simulator and navigate to DNA Insights. Verify:
- [ ] Hero card shows state + prediction + trend
- [ ] Helix 3D floats without clipped rectangle
- [ ] Tier badge appears on helix overlay
- [ ] Health section shows collapsed state (stable/caution/alert)
- [ ] Tapping any section expands/collapses it
- [ ] Motif section shows heatmap bar
- [ ] Base pairs show human-readable phrases
- [ ] Similarity shows sparkline
- [ ] Footer shows tier motivation (if not full tier)
- [ ] Scroll-to works when tapping a motif week on helix
- [ ] Questionnaire banner still appears when available
- [ ] Pull-to-refresh still works
