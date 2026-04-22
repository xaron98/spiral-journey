# Full Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all CRITICAL, HIGH, and key MEDIUM findings from the 6-area audit (concurrency, safety, SwiftUI, localization, persistence, widget/watch).

**Architecture:** Surgical fixes — each task targets one specific finding. No refactors beyond what's needed. Ordered by severity: CRITICALs first, then HIGHs, then MEDIUMs.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, CoreML, CloudKit, WidgetKit, WatchKit

---

### Task 1: Fix MLPredictionEngine data race (CRITICAL)

**Files:**
- Modify: `spiral journey project/Services/MLPredictionEngine.swift:21-29`

The `model` and `isNNModel` static vars are accessed from both MainActor and `Task.detached` in ModelTrainingService. Fix by adding `@MainActor` to the enum — CoreML prediction is fast (~1ms).

- [ ] **Step 1: Add @MainActor to MLPredictionEngine**

Change line 21 from:
```swift
enum MLPredictionEngine {
```
to:
```swift
@MainActor enum MLPredictionEngine {
```

- [ ] **Step 2: Build to verify no compiler errors**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "error:|warning:" | head -20`

If there are errors about calling @MainActor from non-isolated context in ModelTrainingService, wrap those calls in `await MainActor.run { }`.

---

### Task 2: Fix PeerComparisonManager missing @MainActor (CRITICAL)

**Files:**
- Modify: `spiral journey project/Services/PeerComparisonManager.swift:10-11`

All delegate callbacks already hop to MainActor via `Task { @MainActor in }`. Making the class @MainActor is consistent.

- [ ] **Step 1: Add @MainActor to PeerComparisonManager**

Change line 10-11 from:
```swift
@Observable
final class PeerComparisonManager: NSObject {
```
to:
```swift
@MainActor @Observable
final class PeerComparisonManager: NSObject {
```

- [ ] **Step 2: Mark delegate conformance methods as nonisolated**

The MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate methods are called from background threads. They must be `nonisolated`. They already dispatch to MainActor internally, so just add the `nonisolated` keyword to each delegate method.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "error:|warning:" | head -20`

---

### Task 3: Fix force unwraps in DNAMotifSection and DNAAlignmentSection (HIGH)

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAMotifSection.swift:42`
- Modify: `spiral journey project/Views/DNA/DNAAlignmentSection.swift:42`

Both use `.sorted{}.first!` which crashes if the array is empty.

- [ ] **Step 1: Fix DNAMotifSection.swift:42**

Change:
```swift
        let topMotif = profile.motifs.sorted { $0.instanceCount > $1.instanceCount }.first!
```
to:
```swift
        guard let topMotif = profile.motifs.max(by: { $0.instanceCount < $1.instanceCount }) else { return }
```

- [ ] **Step 2: Fix DNAAlignmentSection.swift:42**

Change:
```swift
        let best = profile.alignments.sorted { $0.similarity > $1.similarity }.first!
```
to:
```swift
        guard let best = profile.alignments.max(by: { $0.similarity < $1.similarity }) else { return }
```

Note: `max(by:)` is also more efficient (O(n) vs O(n log n)).

- [ ] **Step 3: Build to verify**

---

### Task 4: Wrap print() statements in #if DEBUG (HIGH)

**Files:**
- Modify: `spiral journey project/spiral_journey_projectApp.swift:43,48`
- Modify: `spiral journey project/Services/WatchSyncBridge.swift:37`
- Modify: `spiral journey project/Services/DataExporter.swift:42`

- [ ] **Step 1: Fix spiral_journey_projectApp.swift**

Change line 43:
```swift
            print("[SwiftData] Container failed: \(error). Retrying with fresh store…")
```
to:
```swift
            #if DEBUG
            print("[SwiftData] Container failed: \(error). Retrying with fresh store…")
            #endif
```

Change line 48:
```swift
            print("[SwiftData] Failed after reset: \(error). Falling back to in-memory store.")
```
to:
```swift
            #if DEBUG
            print("[SwiftData] Failed after reset: \(error). Falling back to in-memory store.")
            #endif
```

- [ ] **Step 2: Fix WatchSyncBridge.swift:37**

Change:
```swift
            print("[WatchSyncBridge] Failed: \(error)")
```
to:
```swift
            #if DEBUG
            print("[WatchSyncBridge] Failed: \(error)")
            #endif
```

- [ ] **Step 3: Fix DataExporter.swift:42**

Change:
```swift
            print("[DataExporter] Export failed: \(error)")
```
to:
```swift
            #if DEBUG
            print("[DataExporter] Export failed: \(error)")
            #endif
```

- [ ] **Step 4: Build to verify**

---

### Task 5: Watch drawEventMarkers — add geo.opacity (HIGH)

**Files:**
- Modify: `Spiral Watch App Watch App/WatchSpiralView.swift:587-596`

Events hard-cut at window edge instead of fading. Must multiply by `geo.opacity(turns:)`.

- [ ] **Step 1: Add opacity to drawEventMarkers**

Change lines 587-596 from:
```swift
    private func drawEventMarkers(context: GraphicsContext, geo: FlatGeo) {
        for event in events {
            let t = event.absoluteHour / period
            guard geo.isVisible(turns: t) else { continue }
            let p = geo.point(turns: t)
            let color = Color(hex: event.type.hexColor)
            let r: CGFloat = 5.0
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color))
        }
    }
```
to:
```swift
    private func drawEventMarkers(context: GraphicsContext, geo: FlatGeo) {
        for event in events {
            let t = event.absoluteHour / period
            guard geo.isVisible(turns: t) else { continue }
            let alpha = geo.opacity(turns: t)
            guard alpha > 0.01 else { continue }
            let p = geo.point(turns: t)
            let color = Color(hex: event.type.hexColor).opacity(alpha)
            let r: CGFloat = 5.0
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color))
        }
    }
```

---

### Task 6: Watch drawLiveAwakeExtension — add geo.opacity (HIGH)

**Files:**
- Modify: `Spiral Watch App Watch App/WatchSpiralView.swift:652-679`

Vigilia path doesn't fade at window edge. Must multiply opacity per segment.

- [ ] **Step 1: Add opacity to drawLiveAwakeExtension**

Change lines 652-679 from:
```swift
    private func drawLiveAwakeExtension(context: GraphicsContext, geo: FlatGeo) {
        let dataEnd = dataEndTurns()
        let cursorTurns = cursorAbsHour / period
        guard cursorTurns > dataEnd + 0.01 else { return }

        let startT = dataEnd
        let endT = cursorTurns
        let awakeColor = Color(hex: "fbbf24").opacity(0.7) // amber, same as iPhone
        let lw: CGFloat = 6.0

        var path = Path()
        var started = false
        let step = 0.02
        var t = startT

        while t <= endT {
            let pt = geo.point(turns: t)
            if !started { path.move(to: pt); started = true }
            else { path.addLine(to: pt) }
            if t >= endT { break }
            t = min(t + step, endT)
        }

        if started {
            context.stroke(path, with: .color(awakeColor),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
    }
```
to:
```swift
    private func drawLiveAwakeExtension(context: GraphicsContext, geo: FlatGeo) {
        let dataEnd = dataEndTurns()
        let cursorTurns = cursorAbsHour / period
        guard cursorTurns > dataEnd + 0.01 else { return }

        let startT = dataEnd
        let endT = cursorTurns
        let lw: CGFloat = 6.0

        var prev: CGPoint?
        let step = 0.02
        var t = startT

        while t <= endT {
            let pt = geo.point(turns: t)
            if let p0 = prev {
                let midT = t - step / 2
                let alpha = geo.opacity(turns: midT) * 0.7
                if alpha > 0.01 {
                    var seg = Path()
                    seg.move(to: p0)
                    seg.addLine(to: pt)
                    context.stroke(seg, with: .color(Color(hex: "fbbf24").opacity(alpha)),
                                   style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            }
            prev = pt
            if t >= endT { break }
            t = min(t + step, endT)
        }
    }
```

---

### Task 7: Watch drawDayRings — add geo.opacity (HIGH)

**Files:**
- Modify: `Spiral Watch App Watch App/WatchSpiralView.swift:404-421`

Day ring circles hard-cut at window edge.

- [ ] **Step 1: Add opacity to drawDayRings**

Change lines 404-421 from:
```swift
    private func drawDayRings(context: GraphicsContext, geo: FlatGeo) {
        let firstDay = max(1, Int(floor(geo.renderFrom)))
        let lastDay = Int(ceil(geo.renderUpTo))
        guard lastDay >= firstDay else { return }
        for day in firstDay...lastDay {
            let t = Double(day)
            guard geo.isVisible(turns: t) else { continue }
            let isWeek = day % 7 == 0
            let color = Color.white.opacity(isWeek ? 0.15 : 0.07)
            let lw: CGFloat = isWeek ? 0.6 : 0.3
            var path = Path()
            for i in 0...60 {
                let frac = Double(i) / 60.0
                let pt = geo.point(turns: t + frac)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: lw)
        }
    }
```
to:
```swift
    private func drawDayRings(context: GraphicsContext, geo: FlatGeo) {
        let firstDay = max(1, Int(floor(geo.renderFrom)))
        let lastDay = Int(ceil(geo.renderUpTo))
        guard lastDay >= firstDay else { return }
        for day in firstDay...lastDay {
            let t = Double(day)
            guard geo.isVisible(turns: t) else { continue }
            let alpha = geo.opacity(turns: t)
            guard alpha > 0.01 else { continue }
            let isWeek = day % 7 == 0
            let baseAlpha = isWeek ? 0.15 : 0.07
            let color = Color.white.opacity(baseAlpha * alpha)
            let lw: CGFloat = isWeek ? 0.6 : 0.3
            var path = Path()
            for i in 0...60 {
                let frac = Double(i) / 60.0
                let pt = geo.point(turns: t + frac)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: lw)
        }
    }
```

- [ ] **Step 2: Build Watch to verify**

Run: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS 2>&1 | grep -E "error:|warning:" | head -20`

---

### Task 8: SDCircadianEvent — add source field (MEDIUM)

**Files:**
- Modify: `spiral journey project/Models/SDCircadianEvent.swift`

Events round-tripped through SwiftData lose `.healthKit` vs `.manual`, breaking dedup and CloudKit gating.

- [ ] **Step 1: Add source property to SDCircadianEvent**

After line 20 (`var durationHours: Double?`), add:
```swift
    /// Event source: "manual" or "healthKit". Defaults to "manual" for backward compat.
    var source: String?
```

- [ ] **Step 2: Update init(from event:) converter**

Change lines 43-51 to include source:
```swift
    convenience init(from event: CircadianEvent) {
        self.init(
            eventID: event.id,
            type: event.type.rawValue,
            absoluteHour: event.absoluteHour,
            timestamp: event.timestamp,
            note: event.note,
            durationHours: event.durationHours
        )
        self.source = event.source.rawValue
    }
```

- [ ] **Step 3: Update toCircadianEvent() converter**

Change lines 55-64 to restore source:
```swift
    func toCircadianEvent() -> CircadianEvent {
        CircadianEvent(
            id: eventID,
            type: EventType(rawValue: type) ?? .light,
            absoluteHour: absoluteHour,
            timestamp: timestamp,
            note: note,
            durationHours: durationHours,
            source: source.flatMap { EventSource(rawValue: $0) } ?? .manual
        )
    }
```

- [ ] **Step 4: Build to verify**

Note: `source` is optional (`String?`) so SwiftData handles schema migration automatically — existing records get `nil` which maps to `.manual` default. No explicit migration needed.

---

### Task 9: CloudRecordConverter depthScale default (MEDIUM)

**Files:**
- Modify: `spiral journey project/Services/CloudRecordConverter.swift:141`

Default fallback is `1.5` but should be `0.15`.

- [ ] **Step 1: Fix depthScale default**

Change line 141 from:
```swift
    let depthScale      = record["depthScale"] as? Double ?? 1.5
```
to:
```swift
    let depthScale      = record["depthScale"] as? Double ?? 0.15
```

- [ ] **Step 2: Build to verify**

---

### Task 10: SleepRecord + WatchSlimRecord Codable backward compat (MEDIUM)

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Models/SleepRecord.swift`
- Modify: `spiral journey project/Services/WatchConnectivityManager.swift:93-108`

`driftMinutes: Double` is non-optional with no custom decoder. Old JSON without this field crashes decode.

- [ ] **Step 1: Add custom decoder to SleepRecord**

After line 42 (closing brace of `init`), add:
```swift

    private enum CodingKeys: String, CodingKey {
        case id, day, date, isWeekend, bedtimeHour, wakeupHour
        case sleepDuration, phases, hourlyActivity, cosinor, driftMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        day = try c.decode(Int.self, forKey: .day)
        date = try c.decode(Date.self, forKey: .date)
        isWeekend = try c.decode(Bool.self, forKey: .isWeekend)
        bedtimeHour = try c.decode(Double.self, forKey: .bedtimeHour)
        wakeupHour = try c.decode(Double.self, forKey: .wakeupHour)
        sleepDuration = try c.decode(Double.self, forKey: .sleepDuration)
        phases = try c.decode([PhaseInterval].self, forKey: .phases)
        hourlyActivity = try c.decode([HourlyActivity].self, forKey: .hourlyActivity)
        cosinor = try c.decode(CosinorResult.self, forKey: .cosinor)
        driftMinutes = try c.decodeIfPresent(Double.self, forKey: .driftMinutes) ?? 0
    }
```

- [ ] **Step 2: Add custom decoder to WatchSlimRecord**

In WatchConnectivityManager.swift, after the `WatchSlimRecord` struct's `toSleepRecord()` method (line 118), add:
```swift

       private enum CodingKeys: String, CodingKey {
           case day, date, isWeekend, bedtimeHour, wakeupHour, sleepDuration, phases, driftMinutes
       }

       init(from decoder: Decoder) throws {
           let c = try decoder.container(keyedBy: CodingKeys.self)
           day = try c.decode(Int.self, forKey: .day)
           date = try c.decode(Date.self, forKey: .date)
           isWeekend = try c.decode(Bool.self, forKey: .isWeekend)
           bedtimeHour = try c.decode(Double.self, forKey: .bedtimeHour)
           wakeupHour = try c.decode(Double.self, forKey: .wakeupHour)
           sleepDuration = try c.decode(Double.self, forKey: .sleepDuration)
           phases = try c.decode([PhaseInterval].self, forKey: .phases)
           driftMinutes = try c.decodeIfPresent(Double.self, forKey: .driftMinutes) ?? 0
       }
```

- [ ] **Step 3: Build both iOS and SpiralKit to verify**

---

### Task 11: InfoPlist.xcstrings — add privacy string translations (P0)

**Files:**
- Modify: `spiral journey project/InfoPlist.xcstrings`

4 privacy permission strings only have English. Must add ar, ca, de, es, fr, ja, zh-Hans.

- [ ] **Step 1: Add translations for NSCalendarsFullAccessUsageDescription**

Add all 7 language translations to the `NSCalendarsFullAccessUsageDescription` key.

- [ ] **Step 2: Add translations for NSCalendarsUsageDescription**

Same translations (content identical to NSCalendarsFullAccessUsageDescription).

- [ ] **Step 3: Add translations for NSLocalNetworkUsageDescription**

Add all 7 language translations.

- [ ] **Step 4: Add translations for NSMicrophoneUsageDescription**

Add all 7 language translations.

- [ ] **Step 5: Add translations for NSSpeechRecognitionUsageDescription**

Add all 7 language translations.

- [ ] **Step 6: Build to verify xcstrings compiles**

---

### Task 12: Widget StateTimelineProvider — localize hardcoded Spanish strings (P0)

**Files:**
- Modify: `SpiralWidget/StateTimelineProvider.swift:41,44,48,83`
- Modify: `SpiralWidget/StateWidgetEntryView.swift:62`
- Modify: `SpiralWidget/StateWidget.swift:13-14`
- Modify: `SpiralWidget/SpiralWidget.swift:21-22`

Widget target has zero localization. All strings hardcoded in Spanish/English.

- [ ] **Step 1: Localize state labels in StateTimelineProvider**

Change lines 41, 44, 48 from hardcoded Spanish to `String(localized:)`:
```swift
// line 41: "Sincronizado" →
String(localized: "widget.state.synchronized", defaultValue: "Synchronized")
// line 44: "En transicion" →
String(localized: "widget.state.transition", defaultValue: "In Transition")
// line 48: "Desalineado" →
String(localized: "widget.state.misaligned", defaultValue: "Misaligned")
// line 83 placeholder: same pattern
```

- [ ] **Step 2: Localize StateWidgetEntryView**

Change line 62:
```swift
// "Esta noche" →
Text(String(localized: "widget.tonight", defaultValue: "Tonight"))
```

- [ ] **Step 3: Localize widget configuration names**

In StateWidget.swift lines 13-14:
```swift
.configurationDisplayName(String(localized: "widget.state.name", defaultValue: "Sleep Status"))
.description(String(localized: "widget.state.description", defaultValue: "Circadian state and tonight's prediction."))
```

In SpiralWidget.swift lines 21-22:
```swift
.configurationDisplayName(String(localized: "widget.spiral.name", defaultValue: "Spiral"))
.description(String(localized: "widget.spiral.description", defaultValue: "Your sleep spiral."))
```

- [ ] **Step 4: Create Localizable.xcstrings for widget target**

Create `SpiralWidget/Localizable.xcstrings` with all widget keys translated into 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans).

- [ ] **Step 5: Add xcstrings file to widget target in Xcode project**

Ensure the Localizable.xcstrings file is included in the SpiralWidget target's build.

- [ ] **Step 6: Build to verify**

---

### Task 13: WatchHealthKitManager — DispatchQueue.main.async to Task @MainActor (HIGH)

**Files:**
- Modify: `Spiral Watch App Watch App/WatchHealthKitManager.swift:63,89,99-101`

Using `DispatchQueue.main.async` instead of `Task { @MainActor in }` bypasses actor isolation verification.

- [ ] **Step 1: Replace DispatchQueue.main.async with Task { @MainActor in }**

In each location, change:
```swift
DispatchQueue.main.async { [weak self] in
    // ...
}
```
to:
```swift
Task { @MainActor [weak self] in
    // ...
}
```

- [ ] **Step 2: Build Watch to verify**

---

### Task 14: Final build verification

- [ ] **Step 1: Build iOS**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

Expected: BUILD SUCCEEDED with 0 errors.

- [ ] **Step 2: Build Watch**

Run: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS`

Expected: BUILD SUCCEEDED with 0 errors.

- [ ] **Step 3: Run SpiralKit tests**

Run: `cd SpiralKit && swift test`

Expected: All tests pass.
