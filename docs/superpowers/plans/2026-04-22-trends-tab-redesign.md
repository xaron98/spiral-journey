# Trends Tab Redesign — "Editorial Semana" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **PROJECT RULE (from CLAUDE.md):** NEVER commit automatically. Only when user says "commitea" / "haz commit" / "commit". Every "Commit" step below is a SUGGESTION the user will trigger manually.

**Goal:** Restructure `AnalysisTab.swift` into an editorial week-oriented layout: horizontal week carousel, `WeekComparisonCard` as hero wrapped in a purple-gradient container, a single yellow insight card, three horizontal dimension pills, a night-by-night breakdown with sleep-window bars, and chips that open advanced charts as sheets.

**Architecture:** Pure presentation refactor. The analysis engine (`store.analysis`, `ConsistencyLabel`, `TrendAnalysis`, `PeriodogramResults`, `DiscoveryDetector`) is untouched. `WeekComparisonCard` internal implementation is NOT modified — only wrapped in a new container. A new `WeeklyInsightEngine` helper lives in `SpiralKit` to derive the "one thing that matters this week" headline from existing stats.

**Tech Stack:** SwiftUI (ScrollView, LazyHStack, sheets), SpiralKit (SpiralStore, SpiralColors, Color(hex:)), `@AppStorage` for persisting selected week, `Localizable.xcstrings` (+ keys in 8 locales).

---

## Non-goals

Do NOT touch:
- `WeekComparisonCard.swift` internals — the two comparison spirals stay exactly as they are. Only wrap it.
- `SpiralStore.swift` analysis pipeline — no new derived state on the store.
- `PDFReportGenerator` — the PDF flow keeps working.
- `SpiralColors` palette — reuse `.bg`, `.card`, `.text`, `.subtle`, `.muted`, `.accent`, `.good`, `.moderate`, `.poor`, `.border`.

---

## File Map

### Create — SpiralKit
| File | Responsibility |
|------|---------------|
| `SpiralKit/Sources/SpiralKit/Analysis/WeeklyInsightEngine.swift` | Pure function: given records + stats + consistency, returns `WeeklyInsight?` with kicker/headline/supporting. Priority: `socialJetlag > weekendDrift > consistencyDrop > durationLoss > goodStreak`. |

### Create — App views
| File | Responsibility |
|------|---------------|
| `spiral journey project/Views/Analysis/WeekCarousel.swift` | Horizontal scrolling chips (S16 · S15 · S14 …). Snap-to-chip. Binds to `selectedWeekOffset`. |
| `spiral journey project/Views/Analysis/WeekVsWeekHero.swift` | Purple-gradient container that wraps `WeekComparisonCard` + "SEMANA VS SEMANA" kicker. |
| `spiral journey project/Views/Analysis/InsightCard.swift` | Yellow-accent card with left 3pt border, kicker, headline, supporting text. Green variant when score > 75. |
| `spiral journey project/Views/Analysis/DimensionPill.swift` | Compact pill: `LABEL / VALUE / unit`, color driven by state. Used by the 3-pill row. |
| `spiral journey project/Views/Analysis/NightByNightCard.swift` | 7 rows with day/time/in-bed-window bar/duration + a bottom hour legend. |
| `spiral journey project/Views/Analysis/AdvancedChipsScroll.swift` | Horizontal chip row that presents 9 advanced chart sheets. |

### Modify
| File | Change |
|------|--------|
| `spiral journey project/Views/Tabs/AnalysisTab.swift` | Full body rewrite against the new composition. Remove `showFullAnalysis`, `scoreCard`, `trendArrowsCard`, `fullAnalysisToggle`, `chartToggles`, and the 3 legacy vertical trend cards. Add `@AppStorage("analysis.selectedWeekOffset")` and the chart-sheet state flags. |
| `spiral journey project/Localizable.xcstrings` | Add ~15 new keys in 8 locales (`analysis.header.*`, `analysis.insight.*`, `analysis.nightByNight.*`, `analysis.advanced.*`, `analysis.empty.week`, dimension labels). |

### Delete (at the end, after the migration works)
The legacy helpers inside `AnalysisTab.swift` go away as part of Task 8 (no separate files to remove):
- `consistencyTrendCard`, `driftTrendCard`, `durationTrendCard` (replaced by `DimensionPill` row)
- `trendArrowsCard(_:)` (replaced by `InsightCard`)
- `scoreCard` (week hierarchy replaces global score)
- `fullAnalysisToggle`, `showFullAnalysis` state (advanced charts live in sheets now)
- `chartToggles` (replaced by `AdvancedChipsScroll`)

---

## Design tokens (from handoff §6)

| Role | Token |
|------|-------|
| Primary / purple | `SpiralColors.accent` (or `Color(hex: "8B5CF6")`) |
| Good (score ≥ 70) | `SpiralColors.good` |
| Moderate | `SpiralColors.moderate` |
| Poor | `SpiralColors.poor` |
| Border subtle | `Color.white.opacity(0.08)` |
| Border accent | `Color.white.opacity(0.14)` |
| Card background | `SpiralColors.card` |
| App background | `SpiralColors.bg` |

Typography:
- Sans: default system
- Mono: `.monospaced()` design — used for kickers, numerical values, timestamps, day labels.

---

## Task 1: WeeklyInsightEngine

**Files:**
- Create: `SpiralKit/Sources/SpiralKit/Analysis/WeeklyInsightEngine.swift`

- [ ] **Step 1.1: Write WeeklyInsightEngine.swift**

```swift
import Foundation

/// A single, human-readable "what matters this week" headline derived
/// from the aggregate stats. The rest of AnalysisTab can surface other
/// data, but the insight card shows exactly one of these — the first
/// rule below (in priority order) that clears its threshold wins.
///
/// Priority:
///   1. Social jet lag ≥ 1h
///   2. Weekend drift (weekend bedtime significantly later than weekdays)
///   3. Consistency dropped vs previous week by ≥ 10 points
///   4. Duration down ≥ 0.5h vs previous window
///   5. (Positive) Consistency ≥ 75 and no regressions → "good streak"
public struct WeeklyInsight: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case socialJetlag
        case weekendDrift
        case consistencyDrop
        case durationLoss
        case goodStreak
    }

    public let kind: Kind
    /// Short uppercase tag ("INSIGHT CLAVE", "BIEN HECHO").
    public let kickerKey: String
    /// Primary one-liner. Contains %@ placeholders filled by `headlineArgs`.
    public let headlineKey: String
    public let headlineArgs: [String]
    /// Secondary context. Optional — some insights don't have one.
    public let supportingKey: String?
    public let supportingArgs: [String]

    public init(kind: Kind,
                kickerKey: String,
                headlineKey: String,
                headlineArgs: [String] = [],
                supportingKey: String? = nil,
                supportingArgs: [String] = []) {
        self.kind = kind
        self.kickerKey = kickerKey
        self.headlineKey = headlineKey
        self.headlineArgs = headlineArgs
        self.supportingKey = supportingKey
        self.supportingArgs = supportingArgs
    }
}

public enum WeeklyInsightEngine {

    /// Derive the highest-priority insight for `records` (the last 7
    /// nights by convention) using stats already computed by the engine.
    ///
    /// Returns nil if there is not enough data (<3 nights) OR no rule
    /// clears its threshold.
    public static func generate(
        records: [SleepRecord],
        stats: SleepStats,
        consistency: SpiralConsistencyScore?
    ) -> WeeklyInsight? {
        guard records.count >= 3 else { return nil }

        // 1. Social jet lag (minutes → hours with 1-decimal formatting).
        if stats.socialJetlag >= 60 {
            let hours = stats.socialJetlag / 60.0
            return WeeklyInsight(
                kind: .socialJetlag,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.socialJetlag",
                headlineArgs: [String(format: "%.1fh", hours)],
                supportingKey: "analysis.insight.socialJetlagConsequence")
        }

        // 2. Weekend drift: avg weekend bedtime later than weekday by ≥ 1h.
        let weekdayBedtimes = records.filter { !$0.isWeekend }.map { $0.bedtimeHour }
        let weekendBedtimes = records.filter { $0.isWeekend }.map { $0.bedtimeHour }
        if weekdayBedtimes.count >= 2, weekendBedtimes.count >= 1 {
            let weekdayMean = circularMeanHour(weekdayBedtimes)
            let weekendMean = circularMeanHour(weekendBedtimes)
            let delta = hoursLater(weekendMean, than: weekdayMean)
            if delta >= 1.0 {
                return WeeklyInsight(
                    kind: .weekendDrift,
                    kickerKey: "analysis.insight.kicker",
                    headlineKey: "analysis.insight.weekendDrift",
                    headlineArgs: [String(format: "%.1fh", delta)],
                    supportingKey: "analysis.insight.weekendDriftConsequence")
            }
        }

        // 3. Consistency dropped ≥ 10 points vs previous week.
        if let c = consistency, let delta = c.deltaVsPreviousWeek, delta <= -10 {
            return WeeklyInsight(
                kind: .consistencyDrop,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.consistencyDrop",
                headlineArgs: [String(format: "%d", Int(abs(delta)))],
                supportingKey: "analysis.insight.consistencyDropConsequence")
        }

        // 4. Mean sleep duration noticeably low (< 6.5h).
        if stats.meanSleepDuration > 0, stats.meanSleepDuration < 6.5 {
            let deficit = 7.5 - stats.meanSleepDuration
            return WeeklyInsight(
                kind: .durationLoss,
                kickerKey: "analysis.insight.kicker",
                headlineKey: "analysis.insight.durationLoss",
                headlineArgs: [String(format: "%.1fh", stats.meanSleepDuration),
                               String(format: "%.1fh", deficit)])
        }

        // 5. Positive case: score ≥ 75 and SRI ≥ 75.
        if let c = consistency, c.score >= 75, stats.sri >= 75 {
            return WeeklyInsight(
                kind: .goodStreak,
                kickerKey: "analysis.insight.goodKicker",
                headlineKey: "analysis.insight.goodStreak",
                headlineArgs: [String(format: "%d", c.score)])
        }

        return nil
    }

    // MARK: - Helpers

    /// Circular mean for hours-of-day (0..24). Preserves the fact that
    /// 23h and 1h are 2 hours apart, not 22.
    private static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let radians = hours.map { $0 / 24.0 * 2 * .pi }
        let sinMean = radians.map(sin).reduce(0, +) / Double(hours.count)
        let cosMean = radians.map(cos).reduce(0, +) / Double(hours.count)
        var angle = atan2(sinMean, cosMean)
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi) * 24.0
    }

    /// Smallest non-negative delta in hours such that
    /// `shifted = reference + delta` (mod 24) equals `later`.
    private static func hoursLater(_ later: Double, than reference: Double) -> Double {
        var delta = later - reference
        while delta < 0 { delta += 24 }
        while delta >= 24 { delta -= 24 }
        // If the result is > 12 the other direction is shorter — treat
        // that as an "earlier" shift (no drift) by returning 0.
        return delta > 12 ? 0 : delta
    }
}
```

- [ ] **Step 1.2: Build iOS**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 1.3: Suggest commit** → `feat(analysis): add WeeklyInsightEngine`

---

## Task 2: WeekCarousel

**Files:**
- Create: `spiral journey project/Views/Analysis/WeekCarousel.swift`

- [ ] **Step 2.1: Write WeekCarousel**

```swift
import SwiftUI
import SpiralKit

/// Horizontal chip carousel for selecting which week the Trends tab
/// should focus on. The newest chip is rightmost (S current); older
/// weeks scroll off to the left. When the set of available weeks is
/// wider than the screen, the chip row is horizontally scrollable.
///
/// Taps update `selectedOffset` (0 = this week, 1 = last week, …).
struct WeekCarousel: View {
    /// Total number of complete 7-night windows the data covers
    /// (minimum 1). Determines how many chips are shown.
    let availableWeeks: Int
    /// 0 = current week, 1 = previous, …
    @Binding var selectedOffset: Int

    private var entries: [Entry] {
        guard availableWeeks > 0 else { return [] }
        let today = Date()
        let cal = Calendar.current
        return (0..<availableWeeks).map { offset in
            let date = cal.date(byAdding: .weekOfYear, value: -offset, to: today) ?? today
            let week = cal.component(.weekOfYear, from: date)
            return Entry(offset: offset, label: "S\(week)")
        }
    }

    private struct Entry: Identifiable {
        let offset: Int
        let label: String
        var id: Int { offset }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Oldest first → newest last so the current week sits
                    // at the trailing edge, matching the reading order.
                    ForEach(entries.reversed()) { entry in
                        chip(entry)
                            .id(entry.offset)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(selectedOffset, anchor: .trailing)
            }
            .onChange(of: selectedOffset) { _, new in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func chip(_ entry: Entry) -> some View {
        let isSelected = entry.offset == selectedOffset
        return Button {
            selectedOffset = entry.offset
        } label: {
            Text(entry.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? .white : SpiralColors.subtle)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                    ? AnyShapeStyle(SpiralColors.accent.opacity(0.25))
                    : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? SpiralColors.accent.opacity(0.45) : Color.clear,
                                lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

- [ ] **Step 2.2: Build + suggest commit** → `feat(analysis): WeekCarousel`

---

## Task 3: InsightCard

**Files:**
- Create: `spiral journey project/Views/Analysis/InsightCard.swift`

- [ ] **Step 3.1: Write InsightCard**

```swift
import SwiftUI
import SpiralKit

/// Yellow-accent card (or green for positive variant) that surfaces a
/// single "what matters this week" finding. Consumed from a
/// `WeeklyInsight` produced by `WeeklyInsightEngine`.
struct InsightCard: View {
    let insight: WeeklyInsight
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 0) {
            // 3pt accent rail on the leading edge.
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized(insight.kickerKey))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(accentColor)
                Text(formatted(insight.headlineKey, args: insight.headlineArgs))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)
                    .lineSpacing(2)
                if let support = insight.supportingKey {
                    Text(formatted(support, args: insight.supportingArgs))
                        .font(.system(size: 12))
                        .foregroundStyle(SpiralColors.subtle)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SpiralColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accentColor: Color {
        insight.kind == .goodStreak ? SpiralColors.good : SpiralColors.moderate
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    private func formatted(_ key: String, args: [String]) -> String {
        let template = localized(key)
        guard !args.isEmpty else { return template }
        // %@ substitution with CVarArg variadic. Cast each String to
        // CVarArg since %@ expects Obj-C NSObject on Swift/Darwin.
        let cvarargs: [CVarArg] = args.map { $0 as CVarArg }
        return String(format: template, arguments: cvarargs)
    }
}
```

- [ ] **Step 3.2: Build + suggest commit** → `feat(analysis): InsightCard`

---

## Task 4: DimensionPill

**Files:**
- Create: `spiral journey project/Views/Analysis/DimensionPill.swift`

- [ ] **Step 4.1: Write DimensionPill**

```swift
import SwiftUI
import SpiralKit

/// Compact horizontal pill for one of the three weekly dimensions
/// (Consistency / Drift / Duration). Used in a 3-pill HStack replacing
/// the previous full-width trend cards.
struct DimensionPill: View {
    /// ALL-CAPS monospaced label, e.g. "CONSISTENCIA".
    let label: String
    /// Main numeric value, e.g. "36" or "-1.4h".
    let value: String
    /// Optional trailing unit, e.g. "/100".
    let unit: String?
    /// Color tint of the value (good / moderate / poor / muted).
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SpiralColors.subtle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpiralColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 4.2: Build + suggest commit** → `feat(analysis): DimensionPill`

---

## Task 5: NightByNightCard

**Files:**
- Create: `spiral journey project/Views/Analysis/NightByNightCard.swift`

- [ ] **Step 5.1: Write NightByNightCard**

```swift
import SwiftUI
import SpiralKit

/// Editorial "noche por noche" breakdown: seven rows, one per night,
/// showing the actual sleep window as a colored bar on a 20h → 10h
/// time axis. Purple = within the user's consistency band, yellow =
/// outlier (late bedtime / very short duration).
struct NightByNightCard: View {
    /// Up to 7 records — callers pass `store.records.suffix(7)`.
    let records: [SleepRecord]
    /// Threshold in hours from the weekly median bedtime beyond which
    /// a night is flagged as inconsistent (yellow bar instead of purple).
    var consistencyToleranceHours: Double = 1.0

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "analysis.nightByNight.title", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)

            VStack(spacing: 0) {
                ForEach(Array(displayRecords.enumerated()), id: \.offset) { idx, entry in
                    row(entry)
                    if idx < displayRecords.count - 1 {
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            }

            axisLegend
        }
        .padding(14)
        .background(SpiralColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Row

    private func row(_ entry: NightEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.dayLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
                .frame(width: 32, alignment: .leading)

            Text(entry.bedtimeLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(entry.consistent ? SpiralColors.text : SpiralColors.poor)
                .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill((entry.consistent ? SpiralColors.accent : SpiralColors.moderate)
                              .opacity(0.85))
                        .frame(
                            width: max(0, min(geo.size.width - entry.leftOffset * geo.size.width,
                                              entry.widthFraction * geo.size.width)),
                            height: 6)
                        .offset(x: entry.leftOffset * geo.size.width)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(entry.durationLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var axisLegend: some View {
        HStack {
            Spacer().frame(width: 32 + 52 + 10 + 10)   // align with bar track
            Text("20h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("00h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("04h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("08h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer().frame(width: 34)
        }
    }

    // MARK: - Mapping

    private struct NightEntry {
        let dayLabel: String
        let bedtimeLabel: String
        let durationLabel: String
        let leftOffset: Double    // 0…1 inside the 14h window
        let widthFraction: Double
        let consistent: Bool
    }

    private var displayRecords: [NightEntry] {
        guard !records.isEmpty else { return [] }
        let medianBedtime = records.map { $0.bedtimeHour }.sorted()[records.count / 2]
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "EEE"
        return records.map { rec in
            // Map clock hours [20..24) ∪ [0..10) → [0..14).
            let startAbs = rec.bedtimeHour < 12
                ? rec.bedtimeHour + 24
                : rec.bedtimeHour
            let left = max(0, min(1, (startAbs - 20) / 14))
            let width = max(0.03, min(1 - left, rec.sleepDuration / 14))
            let consistent = abs(rec.bedtimeHour - medianBedtime) <= consistencyToleranceHours
                || abs(rec.bedtimeHour - medianBedtime) >= (24 - consistencyToleranceHours)
            return NightEntry(
                dayLabel: fmt.string(from: rec.date).capitalized,
                bedtimeLabel: formatHour(rec.bedtimeHour),
                durationLabel: String(format: "%.1fh", rec.sleepDuration),
                leftOffset: left,
                widthFraction: width,
                consistent: consistent)
        }
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h) % 24
        let mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }
}
```

- [ ] **Step 5.2: Build + suggest commit** → `feat(analysis): NightByNightCard`

---

## Task 6: WeekVsWeekHero

**Files:**
- Create: `spiral journey project/Views/Analysis/WeekVsWeekHero.swift`

- [ ] **Step 6.1: Write WeekVsWeekHero**

```swift
import SwiftUI
import SpiralKit

/// Purple-gradient container that wraps the existing WeekComparisonCard
/// as the hero of the Trends tab. The card's internal 3D spirals are
/// untouched; this file only owns the outer chrome.
struct WeekVsWeekHero: View {
    let records: [SleepRecord]
    let spiralType: SpiralType
    let period: Double
    /// Tint of the gradient: purple for the usual case, green when the
    /// caller detected a "good week" (consistency + SRI both ≥ 75).
    var good: Bool = false

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "analysis.hero.kicker", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(kickerColor)

            WeekComparisonCard(
                records: records,
                spiralType: spiralType,
                period: period)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [tintColor.opacity(0.15), SpiralColors.card.opacity(0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(tintColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var tintColor: Color {
        good ? SpiralColors.good : SpiralColors.accent
    }

    private var kickerColor: Color {
        good ? SpiralColors.good : SpiralColors.accent
    }
}
```

- [ ] **Step 6.2: Build + suggest commit** → `feat(analysis): WeekVsWeekHero wrapper`

---

## Task 7: AdvancedChipsScroll

**Files:**
- Create: `spiral journey project/Views/Analysis/AdvancedChipsScroll.swift`

Presents 9 existing chart views in sheets, one tap each.

- [ ] **Step 7.1: Write AdvancedChipsScroll**

```swift
import SwiftUI
import SpiralKit

/// Horizontal row of chips that replaces the old inline-toggle
/// advanced chart section. Each chip presents its chart as a sheet.
struct AdvancedChipsScroll: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var presented: ChartKind?

    enum ChartKind: String, Identifiable, CaseIterable {
        case cosinor, drift, actogram, prc, hrv, periodogram, timeline, autocorrelation, sectorQuality
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "analysis.advanced.title", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChartKind.allCases) { kind in
                        chip(for: kind)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
        .sheet(item: $presented) { kind in
            sheetBody(for: kind)
        }
    }

    private func chip(for kind: ChartKind) -> some View {
        Button {
            presented = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(for: kind))
                    .font(.system(size: 14))
                    .foregroundStyle(color(for: kind))
                Text(String(localized: String.LocalizationValue(titleKey(for: kind)),
                            bundle: bundle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SpiralColors.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SpiralColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheetBody(for kind: ChartKind) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch kind {
                    case .cosinor:        SlidingCosinorView(records: store.records)
                    case .drift:          DriftChartView(records: store.records)
                    case .actogram:       ActogramView(records: store.records)
                    case .prc:            PRCChartView(events: store.events)
                    case .hrv:            HRVTrendView(hrvData: store.hrvData)
                    case .periodogram:
                        PeriodogramView(
                            periodogramResults: store.analysis.periodogramResults,
                            healthProfiles: store.healthProfiles,
                            recordCount: store.records.count)
                    case .timeline:
                        DiscoveryTimelineView(
                            discoveries: DiscoveryDetector.detect(
                                records: store.records,
                                dnaProfile: store.dnaProfile,
                                consistency: store.analysis.consistency,
                                periodograms: store.analysis.periodogramResults,
                                healthProfiles: store.healthProfiles,
                                events: store.events,
                                startDate: store.startDate))
                    case .autocorrelation: AutocorrelationHeatmapView(records: store.records)
                    case .sectorQuality:   SectorQualityHeatmapView(records: store.records)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", bundle: bundle)) {
                        presented = nil
                    }
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func icon(for kind: ChartKind) -> String {
        switch kind {
        case .cosinor:         return "waveform.path"
        case .drift:           return "chart.line.downtrend.xyaxis"
        case .actogram:        return "calendar"
        case .prc:             return "chart.dots.scatter"
        case .hrv:             return "heart.text.square"
        case .periodogram:     return "chart.bar"
        case .timeline:        return "point.topleft.down.to.point.bottomright.curvepath"
        case .autocorrelation: return "square.grid.4x3.fill"
        case .sectorQuality:   return "circle.grid.2x2"
        }
    }

    private func color(for kind: ChartKind) -> Color {
        switch kind {
        case .cosinor:         return SpiralColors.moderate
        case .drift:           return SpiralColors.accent
        case .actogram:        return .blue
        case .prc:             return SpiralColors.good
        case .hrv:             return SpiralColors.poor
        case .periodogram:     return SpiralColors.accent
        case .timeline:        return SpiralColors.subtle
        case .autocorrelation: return .teal
        case .sectorQuality:   return .orange
        }
    }

    private func titleKey(for kind: ChartKind) -> String {
        "analysis.advanced.\(kind.rawValue).title"
    }
}
```

- [ ] **Step 7.2: Build + suggest commit** → `feat(analysis): AdvancedChipsScroll`

---

## Task 8: AnalysisTab refactor (the big one)

**Files:**
- Modify: `spiral journey project/Views/Tabs/AnalysisTab.swift`

Full body rewrite against the new composition. Keep `generateAndSharePDF()` and helpers untouched.

- [ ] **Step 8.1: Read the file**

Read: `spiral journey project/Views/Tabs/AnalysisTab.swift:1-200` — identify exact line spans of the legacy helpers to delete (`consistencyTrendCard`, `driftTrendCard`, `durationTrendCard`, `trendArrowsCard`, `scoreCard`, `fullAnalysisToggle`, `chartToggles`, `showFullAnalysis`, and the 9 chart toggle state flags).

- [ ] **Step 8.2: Rewrite struct body**

Replace the entire `struct AnalysisTab: View { … }` up to but NOT including `struct TrendDimensionCard`, `CategoryRow`, `RecommendationRow` (keep those — or confirm they are now unused and delete). Target structure:

```swift
struct AnalysisTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @AppStorage("analysis.selectedWeekOffset") private var selectedWeekOffset: Int = 0
    @State private var isGeneratingPDF = false

    var body: some View {
        ZStack {
            SpiralColors.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if store.records.isEmpty {
                        emptyState
                    } else {
                        trendHeader
                        WeekCarousel(
                            availableWeeks: max(1, store.records.count / 7),
                            selectedOffset: $selectedWeekOffset)
                        weekHero
                        if let insight = weeklyInsight {
                            InsightCard(insight: insight)
                        }
                        dimensionsRow
                        NightByNightCard(records: Array(displayRecords.suffix(7)))
                        AdvancedChipsScroll()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Header

    private var trendHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "analysis.header.weekNumber", bundle: bundle),
                            currentWeekNumber))
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(SpiralColors.subtle)
                Text(String(localized: "analysis.header.thisWeek", bundle: bundle))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(SpiralColors.text)
            }
            Spacer()
            Button {
                generateAndSharePDF()
            } label: {
                if isGeneratingPDF {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(SpiralColors.accent)
                }
            }
            .disabled(isGeneratingPDF)
            .accessibilityLabel(String(localized: "analysis.share.pdf", bundle: bundle))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Hero

    private var weekHero: some View {
        WeekVsWeekHero(
            records: displayRecords,
            spiralType: store.spiralType,
            period: store.period,
            good: isGoodWeek)
    }

    // MARK: - Dimensions row

    private var dimensionsRow: some View {
        let c = store.analysis.consistency
        let drift = store.analysis.stats.stdBedtime * 60.0   // minutes
        let duration = store.analysis.stats.meanSleepDuration
        return HStack(spacing: 10) {
            DimensionPill(
                label: String(localized: "analysis.dim.consistency", bundle: bundle),
                value: c.map { "\($0.score)" } ?? "--",
                unit: "/100",
                valueColor: consistencyColor(for: c?.label ?? .insufficient))
            DimensionPill(
                label: String(localized: "analysis.dim.drift", bundle: bundle),
                value: drift > 0 ? String(format: "%dm", Int(drift)) : "--",
                unit: nil,
                valueColor: drift < 45 ? SpiralColors.good
                          : drift < 90 ? SpiralColors.moderate
                          : SpiralColors.poor)
            DimensionPill(
                label: String(localized: "analysis.dim.duration", bundle: bundle),
                value: duration > 0 ? String(format: "%.1fh", duration) : "--",
                unit: nil,
                valueColor: duration >= 7.0 ? SpiralColors.good
                          : duration >= 6.0 ? SpiralColors.moderate
                          : SpiralColors.poor)
        }
    }

    // MARK: - Insight

    private var weeklyInsight: WeeklyInsight? {
        WeeklyInsightEngine.generate(
            records: Array(displayRecords.suffix(7)),
            stats: store.analysis.stats,
            consistency: store.analysis.consistency)
    }

    // MARK: - Derived

    private var displayRecords: [SleepRecord] {
        // selectedWeekOffset 0 = the most recent 7 records; 1 = the 7 before that; …
        let end = store.records.count - selectedWeekOffset * 7
        let start = max(0, end - 7)
        guard start < end else { return [] }
        return Array(store.records[start..<end])
    }

    private var currentWeekNumber: Int {
        let refDate = displayRecords.last?.date ?? Date()
        return Calendar.current.component(.weekOfYear, from: refDate)
    }

    private var isGoodWeek: Bool {
        guard let c = store.analysis.consistency else { return false }
        return c.score >= 75 && store.analysis.stats.sri >= 75
    }

    private func consistencyColor(for label: ConsistencyLabel) -> Color {
        switch label {
        case .veryStable, .stable: return SpiralColors.good
        case .variable:            return SpiralColors.moderate
        case .disorganized:        return SpiralColors.poor
        case .insufficient:        return SpiralColors.muted
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(SpiralColors.muted)
                .padding(.top, 60)
            Text(String(localized: "analysis.empty.title", bundle: bundle))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SpiralColors.text)
            Text(String(localized: "analysis.empty.body", bundle: bundle))
                .font(.system(size: 13))
                .foregroundStyle(SpiralColors.subtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - PDF (unchanged)

    private func generateAndSharePDF() {
        // KEEP THE EXISTING IMPLEMENTATION — copy verbatim from the
        // previous file. This plan does not alter PDF behavior.
    }
}
```

**Important — preserve verbatim from the previous file:** the body of `generateAndSharePDF()`, including any helper types it references.

- [ ] **Step 8.3: Delete now-unused helpers**

Search the file for the old `private var consistencyTrendCard` / `driftTrendCard` / `durationTrendCard` / `trendArrowsCard(_:)` / `scoreCard` / `fullAnalysisToggle` / `chartToggles` and remove their definitions. Also remove the 9 `@State private var showXxx` flags for chart toggles.

If `struct TrendDimensionCard`, `CategoryRow`, `RecommendationRow` at the bottom of the file are no longer referenced, delete them too. Run a grep to confirm they are unused BEFORE deleting.

- [ ] **Step 8.4: Build**

```
xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED. If any of the deleted helpers is still referenced by another file, a compile error will flag it.

- [ ] **Step 8.5: Suggest commit** → `refactor(analysis): AnalysisTab new editorial composition`

---

## Task 9: Good-week variant + sheet titles

**Files:**
- Modify: `spiral journey project/Views/Analysis/WeekVsWeekHero.swift` (minor)
- Modify: `spiral journey project/Views/Tabs/AnalysisTab.swift`

Wire the `good` parameter of `WeekVsWeekHero` to `isGoodWeek`. Already done in Task 8 scaffold — verify. Also, ensure sheet titles in `AdvancedChipsScroll` use the `navigationTitle` for readability:

- [ ] **Step 9.1: Patch AdvancedChipsScroll**

Inside `sheetBody(for:)`, add right before the `.toolbar` modifier:

```swift
.navigationTitle(String(localized: String.LocalizationValue(titleKey(for: kind)), bundle: bundle))
```

- [ ] **Step 9.2: Build + suggest commit** → `feat(analysis): wire good-week tint and sheet titles`

---

## Task 10: Localization (≥ 40 keys × 8 locales)

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

Add:

```
analysis.header.weekNumber             = "Semana %d"                  / "Week %d"
analysis.header.thisWeek               = "Esta semana"                / "This week"
analysis.share.pdf                     = "Compartir informe PDF"      / "Share PDF report"
analysis.hero.kicker                   = "SEMANA VS SEMANA"           / "WEEK VS WEEK"
analysis.dim.consistency               = "CONSISTENCIA"               / "CONSISTENCY"
analysis.dim.drift                     = "DRIFT"                      / "DRIFT"
analysis.dim.duration                  = "DURACIÓN"                   / "DURATION"
analysis.insight.kicker                = "INSIGHT CLAVE"              / "KEY INSIGHT"
analysis.insight.goodKicker            = "BIEN HECHO"                 / "WELL DONE"
analysis.insight.socialJetlag          = "Tu jet lag social ronda las %@" / "Your social jet lag is around %@"
analysis.insight.socialJetlagConsequence = "El lunes arrastras el desfase del fin de semana." / "Monday carries the weekend's misalignment."
analysis.insight.weekendDrift          = "Los fines de semana te acuestas %@ más tarde" / "On weekends you go to bed %@ later"
analysis.insight.weekendDriftConsequence = "Cuesta 2–3 días recuperar un desfase así." / "It takes 2–3 days to recover from a shift like this."
analysis.insight.consistencyDrop       = "Tu consistencia bajó %@ puntos esta semana" / "Consistency dropped %@ points this week"
analysis.insight.consistencyDropConsequence = "Una rutina estable esta noche corta la racha." / "A steady routine tonight breaks the streak."
analysis.insight.durationLoss          = "Duermes %@ de media — te faltan %@" / "You sleep %@ on average — missing %@"
analysis.insight.goodStreak            = "Semana con %@ puntos de consistencia" / "Week with %@ consistency points"

analysis.nightByNight.title            = "NOCHE POR NOCHE"            / "NIGHT BY NIGHT"

analysis.advanced.title                = "ANÁLISIS AVANZADO"          / "ADVANCED ANALYSIS"
analysis.advanced.cosinor.title        = "Cosinor deslizante"         / "Sliding Cosinor"
analysis.advanced.drift.title          = "Drift"                      / "Drift"
analysis.advanced.actogram.title       = "Actograma"                  / "Actogram"
analysis.advanced.prc.title            = "PRC"                        / "PRC"
analysis.advanced.hrv.title            = "HRV"                        / "HRV"
analysis.advanced.periodogram.title    = "Periodograma"               / "Periodogram"
analysis.advanced.timeline.title       = "Línea de tiempo"            / "Timeline"
analysis.advanced.autocorrelation.title = "Autocorrelación"           / "Autocorrelation"
analysis.advanced.sectorQuality.title  = "Calidad por sector"         / "Sector quality"

analysis.empty.title                   = "Aún no hay datos suficientes" / "Not enough data yet"
analysis.empty.body                    = "Añade noches o conecta Apple Salud para ver tus tendencias." / "Add nights or connect Apple Health to see your trends."
analysis.empty.week                    = "Necesitas 2 semanas para comparar" / "You need 2 weeks to compare"

common.done                            = "Hecho"                      / "Done"
```

- [ ] **Step 10.1: Python script**

Use the same Python helper pattern as in earlier i18n tasks (see `2026-04-21-coach-tab-redesign.md` Task 21 and recent `i18n:` commits). Every key gets values in all 8 locales (ar/ca/de/en/es/fr/ja/zh-Hans) with state `translated`. Non-ES/EN use the English value as a best-effort placeholder OR a full translation — the previous `i18n: translate 52 missing keys…` commit used full translations, match that style.

- [ ] **Step 10.2: Build**

```
xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet > /dev/null 2>&1; echo "iOS: $?"
xcodebuild build -scheme "spiral journey project" -destination "platform=macOS" -quiet > /dev/null 2>&1; echo "macOS: $?"
```

Both must return 0.

- [ ] **Step 10.3: Suggest commit** → `i18n(analysis): add Trends redesign keys in 8 locales`

---

## Verification checklist (before declaring the redesign done)

- [ ] Launch iOS sim, go to Trends tab with ≥ 14 nights of real data.
- [ ] Week carousel shows N chips, newest on the right.
- [ ] Hero shows 2 spirals + deltas (WeekComparisonCard untouched).
- [ ] Insight card renders with a sensible headline; changes with data.
- [ ] 3 dimension pills show colors matching ranges.
- [ ] Night-by-night bars stay inside their track for every night (no overflow).
- [ ] Tap each of the 9 advanced chips — each opens as a sheet and closes cleanly.
- [ ] PDF share still works.
- [ ] Empty state shows on a fresh store.
- [ ] Good-week variant: set SRI = 80 manually and verify green tint.
- [ ] Dark mode verified.
- [ ] Build: iOS + macOS + watchOS all succeed.
- [ ] Localization: switch to English locale, spot-check new strings.
- [ ] Accessibility: VoiceOver reads each pill and night row with a combined label.
