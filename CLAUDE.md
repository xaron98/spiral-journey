# Spiral Journey Project

## Git Commit Rules (CRITICAL)
- **NEVER commit automatically.** Only commit when the user explicitly says "commitea", "haz commit", or "commit".
- Do NOT commit after builds succeed, after the user confirms something works, or after completing a feature.
- The user controls when commits happen. Zero exceptions.

## Build
- iOS: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
- Watch: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS`

## Swift Skills (use when writing or reviewing code)
- **swift-best-practices** — Swift 6+ patterns, async/await, actors, MainActor, Sendable, typed throws. Use when writing/reviewing ANY Swift code.
- **swift-concurrency-6-2** — Swift 6.2 approachable concurrency, @concurrent, isolated conformances. Use for concurrency questions and data race fixes.
- **swift-actor-persistence** — Thread-safe actor-based persistence. Use when working on data storage, caching, or fixing data races in persistence code.
- **swift-protocol-di-testing** — Protocol-based DI for testable code. Use when writing tests that need mocks (HealthKit, network, file system).
- **swiftui-patterns** — @Observable, view composition, navigation, performance. Use when working on SwiftUI views.
- **apple-on-device-ai** — Foundation Models, Core ML, MLX Swift. Use for AI/ML features.
- **liquid-glass-design** — iOS 26 Liquid Glass design system. Use for UI styling.

## Key Files
- `spiral journey project/Views/Spiral/SpiralView.swift` — all rendering (Canvas)
- `spiral journey project/Views/Spiral/SpiralVisibilityEngine.swift` — per-day visibility/opacity
- `spiral journey project/Views/Tabs/SpiralTab.swift` — cursor, zoom, gestures
- `SpiralKit/` — geometry, models, shared logic

## Spiral Rendering Rules (CRITICAL)

### Camera & Rendering System
- **Cursor moves freely** — past and future, no limits on movement
- **ALL data always visible** — every day with data renders at full opacity regardless of cursor position. Moving cursor never hides or fades existing data.
- **No opacity fade** — `rawOpacity = 1.0` always. No opacityCurve decay, no segmentEdgeFade. Data paths never disappear.
- **Render bounds** — `renderFrom = 0`, `renderUpTo = max(cursor, extentTurns + 0.5)`. Everything is always in render range.
- **Zoom auto-adjusts** — `autoFitScale` in CameraState ensures nothing projects beyond 85% of canvas when cursor goes to future.
- **User can still pinch-zoom** — changes `span` (visible turns), auto-fit corrects if needed
- **Tap on spiral** — shows info panel for tapped position via `showInfoForCursorPosition()`. Cursor jumps to tap location, camera follows.

### Camera (CameraState)
- `tRef = upToTurns + 0.5` — depth reference point
- `camZ = margin * zStep - focalLen` — camera position (fixed formula)
- `focalLen = maxRadius * 1.6` (3D) or `maxRadius * 1.2` (flat) — 3D has closer initial zoom
- `autoFitScale` — computed per-frame in 3D: scans all visible turns, finds max projected radius, scales to fit 85% of canvas. 1.0 when everything fits, < 1.0 when too large. Flat mode always 1.0.
- Applied in `project()` and `perspectiveScale()` — both position and linewidth scale together

### Visibility (SpiralVisibilityEngine)
- **All days visible** — `rawOpacity = 1.0` always, no distance-based fade
- **Single distance source** — `abs(requestedActiveIndex - dayIndex)` used for blur/strokeScale only
- **segmentEdgeFade** — always returns 1.0 (disabled). No edge clipping.
- Context blocks: visible for all days (0...maxDay), only gated by `behindCursor` (dayIndex <= requestedActiveIndex) and `isActive(on:)`
- Calendar events always visible — not limited to camera window

### Draw Order
- Awake data → sleep data (sleep always on top)
- **Live awake extension** — drawn OUTSIDE the record loop, always extends from data end to cursor position. Not gated by day visibility. This is the vigilia path that grows with the cursor.
- Live awake extension starts from `max(dataEndTurns, tWakeRaw)`, never from wakeupHour alone
- **Backbone** — covers `0` to `max(cursor, extentTurns)`, always visible

### Data Points (drawDataPoints)
- **No isLastRecord exceptions** — all records treated equally
- **No skipEdge** — no edge fade applied
- Records filtered by: `vis.isVisible` (always true) + `isBehindCamera` + `perspectiveScale > 0.04`
- Tap info: `showInfoForCursorPosition()` uses `cursorAbsHour` directly, searches current + adjacent days for sleep detection

### Archimedean Mode
- 2D flat: `startRadius = 75`, `depthScale = 0`, `perspectivePower = 1.0`
- 3D: `startRadius = 40`, `depthScale = store.depthScale` (0.15 default), `perspectivePower = 1.0`
- `spiralExtentTurns = maxReachedTurns`
- Geometry: `radius(t) = startRadius + spacing * t`
- 2D flat: radial zoom maps `[rInner, rOuter] → [0, maxRadius]`
- 3D: perspective `scale = focalLen / dz * autoFitScale`

### Logarithmic 2D Mode (flat)
- Real logarithmic geometry: `radius(t) = startRadius * exp(growthRate * t)`
- `startRadius = 15` — small inner turns, exponential spread visible (distinct from archimedean)
- `depthScale = 0` (flat), `perspectivePower = 1.0`
- `effectiveSpiralExtent` caps at `records.count + 1` (min 7) — prevents growthRate collapse
- `effectiveLinkGrowthToTau` disables tau link when rate ≈ 0

### Logarithmic 3D Mode (SpiralTab `isLog3D`)
- Real logarithmic geometry with boosted perspective params
- `startRadius = 35` — tighter origin for cone effect
- `effectiveDepthScale = max(store.depthScale, 0.5)` — store default is 0.15, needs ≥0.5 for visible cone
- `perspectivePower = 0.5` (sqrt) — softer perspective, spreads arms more evenly
- `effectiveSpiralExtent` caps at `records.count + 1` (min 7)
- `camera.cullThreshold` is dynamic: `pow(0.10, perspPow)` — accounts for sqrt perspective range

### linkGrowthToTau (CRITICAL)
- When `linkGrowthToTau = true` and `period ≈ 24h`: `tauLinkedGrowthRate = log(24/24)/(2π) = 0`
- This makes `growthRate = 0` → ALL turns have same radius → spiral collapses to a single circle
- `effectiveLinkGrowthToTau` detects this and returns `false` when tau rate < 0.001
- This affects BOTH log 2D and log 3D

### Rephase Mode
- Uses `effectiveSpiralType`, `effectiveStartRadius`, `effectiveDepthScale`, `effectivePerspectivePower`, `effectiveSpiralExtent`, `effectiveLinkGrowthToTau` — same as main spiral
- Shows the spiral selected in settings, not hardcoded archimedean

### Pitfalls to Avoid
1. Never use min lineWidth without perspScale guard — creates blobs
2. Never draw live awake extension from wakeupHour — hides sleep data
3. Never show context blocks ahead of cursor
4. Never allow unlimited zoom-out to maxReachedTurns
5. Never pass `maxReachedTurns` directly as `spiralExtentTurns` for logarithmic spirals — use `effectiveSpiralExtent`
6. Never assume `store.depthScale` is 1.5 — default is **0.15**
7. Never enable `linkGrowthToTau` for logarithmic spirals with period=24 — growthRate becomes 0
8. Never use dual-distance opacity (effectiveActiveIndex + requestedActiveIndex) — causes non-monotonic fade
9. Never add isLastRecord exceptions to drawDataPoints — creates fragments
10. Never add window clipping or edge fade to data — ALL data must be visible always
11. Never limit renderFrom/renderUpTo to the camera window — use 0 to extentTurns
12. Never limit context block iteration to window.startIndex...endIndex — use 0...maxDay

## DNA 3D Helix Performance Rules (CRITICAL)

### Gesture & Transform System
- **CADisplayLink at 60fps** — transform applied directly to entity, NOT via SwiftUI `update:` closure
- **@ObservationIgnored** — `rotationX`, `rotationY`, `zoomScale`, `dragStart`, `baseZoom`, `isInteracting` are all `@ObservationIgnored` in `HelixInteractionManager`. They MUST NOT trigger SwiftUI re-renders.
- **Only `selectedWeek` and `showPatterns` are @Observable** — these are the only properties that need SwiftUI updates (for overlays/legend)
- **No @State during drag** — `dragStart` and `baseZoom` live in the manager, not as `@State` in the view
- **No @Binding during drag** — `isInteractingWith3D` is NOT set during drag/pinch gestures. It caused parent ScrollView re-render.
- **`.gesture()` not `.highPriorityGesture()`** — highPriority adds gesture conflict resolution overhead
- **No `contentShape(Rectangle())`** — adds unnecessary hit testing overhead
- **`rootEntity` stored as weak ref in manager** — allows CADisplayLink to apply transform without capturing @State

### Dirty-Tracking in `update:` Closure
- `update:` only runs when `selectedWeek` or `showPatterns` change
- LOD materials: only update when zoom crosses bracket boundary (0.8 or 1.5)
- Motif regions: only update when `showPatterns` toggles
- Week highlights: only update when `selectedWeek` changes

### Pitfalls to Avoid
1. Never make rotation/zoom properties `@Observable` or `@State` — causes re-render on every drag frame
2. Never use `@Binding` changes during continuous gestures (drag/pinch)
3. Never use Timer for transform — use CADisplayLink for 60fps
4. Never apply transform in `update:` closure — it runs on SwiftUI's schedule, not render schedule
5. Never use `highPriorityGesture` or `contentShape` — adds gesture resolution overhead

## Motif Discovery
- Default DTW threshold: **2.0** (not 8.0). With normalized [0,1] features, 8.0 merges everything into one cluster.
- Motif patterns visualized via colored base pair connectors + SwiftUI legend (not 3D cylinders/text)

## Widget Rules (CRITICAL)

### Spiral Widget
- **Always archimedean 2D flat** — no 3D perspective, no depthScale
- **Flat projection only** — use `geo.point()` directly, never 3D perspective math (focalLen/zStep)
- **Re-index records to day 0-6** — last 7 records re-indexed so geometry has only 7 turns
- **Re-base timestamps** — when re-indexing, subtract `baseTimestamp` from all `phase.timestamp` values so they start from 0. Without this, `timestamp/period` gives turns of 60+ which project outside the widget.
- **Use `phase.timestamp / period` for turn calculation** — NOT `dayT + phase.hour / period`. The `hour` field wraps at midnight (23→0) causing lines that cross the entire spiral. Timestamps are continuous and never wrap.
- **`scaleEffect(0.9)`** on the entry view — controls final widget spiral size
- **`startRadius: 1`** — nearly from center
- **`contentMarginsDisabled()`** on the widget configuration — removes iOS system padding
- **Size control via `scaleEffect`** — NOT via `maxDays`, `padding`, or geometry hacks

### State Widget
- Shows circadian state (Sincronizado/En transición/Desalineado) + prediction
- Reads from `spiral-journey-state` key in App Group UserDefaults
- Written by `SpiralStore.writeStateWidgetData()` on every save

### Pitfalls to Avoid
1. Never use `dayT + phase.hour / period` — wraps at midnight, creates visual cuts
2. Never use 3D perspective projection in widget — makes spiral too small or too big
3. Never use `turnOffset` with re-indexed records — causes coordinate mismatch
4. Never change widget size via `maxDays` — use `scaleEffect` instead
5. Never pass records without re-basing timestamps — turns will be 60+ and project outside widget

## Watch Spiral Rules (CRITICAL)

### Rendering
- **Always flat 2D archimedean** — no 3D perspective, no depthScale, no Cam struct
- **Windowed view** — show ~4 days centered on cursor, NOT all data
- **Thick paths** (Activity Rings style) — backbone 6pt, sleep data 8pt, events 5pt, cursor 7pt, marking arc 10pt
- **`turnOffset`** — first visible turn maps to `startRadius`, radius = `startRadius + spacing * (t - turnOffset)`, clamped to ≥ 0
- **Radius clamp** — `max(0, ...)` prevents negative radii that create mirror spirals
- **Filter by window** — only draw records/events where `geo.isVisible(turns:)` is true

### Crown
- Crown moves cursor position along the spiral
- No zoom on Watch — fixed 4-day window follows cursor

### Pitfalls to Avoid
1. Never use perspective projection (Cam/focalLen/zStep) on Watch — always flat
2. Never show all data at once — Watch screen too small, use windowed view (~4 days)
3. Never allow negative radius — clamp with `max(0, ...)` or turns before window produce mirror spirals
4. Never use thin line widths (<3pt) on Watch — illegible on small screen
5. Never store Watch spiral settings (depthScale/spiralType) from iPhone sync — Watch is always flat archimedean

## Code Quality Rules

### Logging
- **All print() statements MUST be wrapped in `#if DEBUG`** — production logs must not leak sleep data, dates, or personal info
- Applies to: SpiralStore, HealthKitManager, WatchHealthKitManager, WatchConnectivityManager

### Safety
- **No force unwraps** on HealthKit types — use modern non-optional API: `HKCategoryType(.sleepAnalysis)` not `HKObjectType.categoryType(forIdentifier:)!`
- **No force unwraps** on `.min()`, `.max()`, `.last` — always `guard let` or `?? default`
- **HR threshold bounds** — always clamp to [110, 180] bpm

### Auto-Events (HealthKit → CircadianEvent)
- Only remove auto-events for days being re-imported (not all `source == .healthKit`)
- Deduplication: ±0.5h same type = duplicate, manual takes priority
- CloudKit skip: `event.source == .manual` only syncs to cloud
- `deletedAutoEventKeys` prevents re-import of user-deleted auto-events

### Localization
- ALL user-facing strings via `String(localized:bundle:)` or `NSLocalizedString(_:bundle:comment:)`
- New features MUST add localization keys to `Localizable.xcstrings` for all 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans)
- JSON content files (Learn) go in `SpiralKit/Sources/SpiralKit/Resources/` with `Bundle.module`

### Codable Backward Compatibility
- New fields on `Codable` structs MUST be optional or use `decodeIfPresent` with fallback
- Dictionary keys with enum types don't auto-synthesize Codable — use arrays instead
- Test: decode JSON without new field → must not crash
