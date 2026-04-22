# Spiral Journey Project

## Git Commit Rules (CRITICAL)
- **NEVER commit automatically.** Only commit when the user explicitly says "commitea", "haz commit", or "commit".
- Do NOT commit after builds succeed, after the user confirms something works, or after completing a feature.
- The user controls when commits happen. Zero exceptions.

## Build
- iOS: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
- macOS: `xcodebuild build -scheme "spiral journey project" -destination "platform=macOS"`
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
- `SpiralGeometry/` — Clifford torus, tesseract, Bures-Wasserstein math (local SPM package)

## NeuroSpiral 4D Rules (CRITICAL)

### Architecture
- **SpiralGeometry module name conflict** — `struct SpiralGeometry` exists in SpiralKit. ALL views must use specific imports: `import struct SpiralGeometry.WearableSleepSample`, `import enum SpiralGeometry.Tesseract`, etc. NEVER use bare `import SpiralGeometry`.
- **Watch does NOT run SpiralGeometry** — iPhone computes, writes summary to App Group UserDefaults, sends via WatchConnectivity applicationContext. Watch only reads.
- **Baseline persisted** — `WearableTo4DMapper.PersonalBaseline` stored in App Group key `"neurospiral-baseline"` as JSON.

### NeuroSpiral Views (Views/DNA/)
- `NeuroSpiralView.swift` — hub dashboard. Computes analysis + perNightAnalyses + retainedSamples in `.task`. Passes data to detail views via NavigationLink. Random walk with momentum 0.90 + drift 0.10 + phase-specific targets.
- `NeuroSpiralTorusDetailView.swift` — toggle 2D (Canvas) / 3D (RealityKit). 2D shows θ/φ scatter, 3D shows donut embedding.
- `NeuroSpiralTrajectoryView.swift` — toggle 2D (Canvas animated) / 3D (RealityKit progressive reveal). Shared play/pause/speed controls.
- `NeuroSpiralTorus3DView.swift` — RealityKit wrapper, `@available(iOS 18.0, *)`. Slider 4D rebuilds geometry via Observable `w4DAngle`.
- `NeuroSpiralTrajectory3DView.swift` — RealityKit progressive reveal, entities pre-built invisible
- `NeuroSpiralTorusInteractionManager.swift` — CADisplayLink 60fps. `w4DAngle` is Observable (triggers rebuild). All other transform state @ObservationIgnored.
- `NeuroSpiralTorusSceneBuilder.swift` — donut embedding: `(R + r·cos(φ))·cos(θ), r·sin(φ), (R + r·cos(φ))·sin(θ)` with R=0.35, r=0.15. Wireframe 8+4 rings. `project4Dto3D` is public static. Uses **direct feature mapping** (HRV, stillness, HR, circadian → torus angles), NOT Takens embedding (which requires raw signals at 100Hz+).
- `NeuroSpiralHistoryView.swift` — sparklines + night list
- `NeuroSpiralExportView.swift` — CSV export + ShareLink
- `SleepTriangleView.swift` — barycentric sleep triangle with empirical centers from 155+ subjects. Schedule-agnostic sleep window detection.
- `DNAInfoSheetView.swift` — SleepDNA educational info (12 sections + macro/micro bridge + helix reading guide)

### Sleep Triangle Rules (UPDATED 2026-04 — W/REM/N3 framework)
- **Layout** — Bottom-left: Wake (dorado). Top: REM (lila, cúspide de la conciencia). Bottom-right: Deep/N3 (azul #7B68EE). One AASM phase per vertex.
- **Schedule-agnostic** — `extractSleepWindow()` finds longest continuous non-awake block, NOT by clock hour. Works for night workers, siestas, split sleep.
- **Barycentric centers** in `(wake, rem, deep)` space:
  - `.awake = (0.85, 0.10, 0.05)` — near Wake vertex
  - `.rem   = (0.20, 0.75, 0.05)` — near REM vertex with noticeable Wake
  - `.light = (0.10, 0.40, 0.50)` — INTERIOR, between REM and Deep (N2 has features of both)
  - `.deep  = (0.05, 0.10, 0.85)` — near Deep vertex
- **N2/light is ALWAYS an interior point** — no dedicated vertex. This is the paper's archetype decomposition; do not re-introduce a 4th vertex.
- **Pill metrics show REAL phase time percentages** (count epochs per phase / total), NOT barycentric averages. Users expect "30% Deep" to mean "30% of the night was N3", not "axis projection 30%".
- **Legend = 4 colored dots** (one per AASM phase) + info note explaining light sits in interior.
- **Summary text** — "Tu noche: X% despierto, Y% REM, Z% sueño ligero, W% profundo". NEVER use "soñando" for the Active pole — it's wrong for N2.
- **Deep points visual** — color `#7B68EE`, radius 5px (vs 2.5px), white border, drawn on top (z-order).
- **Zone tints** — soft colored triangles near each vertex (6% opacity).
- **No trail lines** — removed for clarity. Temporal opacity shows direction (earlier=transparent, later=opaque).
- **Prev framework** (Wake/Active(REM+N2)/Deep) was replaced 2026-04 because lumping REM with N2 contradicted "each vertex = one phase" and confused users.

### 3D Torus Rules
- **Donut embedding** (NOT stereographic) — `(R + r·cos(φ))·cos(θ)` with R=0.35, r=0.15
- **Slider 4D is Observable** — triggers geometry rebuild in `update:` closure. Array() snapshot prevents mutation during child transfer.
- **Zoom range 0.15× to 4.0×** — initial zoom 1.5×
- **CADisplayLink at 60fps** — transform applied directly to entity, NOT via SwiftUI `update:` closure
- **@ObservationIgnored** — `rotationX`, `rotationY`, `zoomScale`, `dragStart`, `baseZoom`, `isInteracting`. Only `w4DAngle` and `selectedEpochIndex` are Observable.
- **Wireframe** — 8 major + 4 minor rings, radius 0.001, opacity 0.03-0.04. No "straight line" artifacts.
- **Vertices** — 16 tesseract vertices, radius 0.008 (dominant: 0.02 green glow). Small, don't compete with trajectory.

### 3D Helix Rules
- **Molecular DNA model** — smooth cylindrical backbones (72 seg/turn, joint spheres hide seams)
- **Gold backbone** = current period (strand 1), **Silver backbone** = comparison period (strand 2)
- **Connector bars** — radius 0.011, phase-colored (gold=wake, violet=REM, blue=NREM gradient)
- **3 comparison modes**: Yesterday, Week, My Best — selector pills in overlay
- **Bar hit-test** — CollisionComponent on parent Entity (width=hitThick, **height=barLength** on Y axis post-rotation). `targetedToAnyEntity()` with parent-chain walk.
- **Phase legend** + strand identity below helix
- **Rebuild on mode change** — `Array(root.children)` snapshot before removal to prevent mutation during iteration

### Comparison Integration
- `ComparisonPayload` has 4 optional torus fields — `vertexDistribution`, `meanWindingRatio`, `torusStability`, `dominantVertex`
- `torusSimilarity()` uses Jensen-Shannon divergence on 16-element vertex distributions
- `SpiralConsistencyCalculator` accepts optional `torusDistributions` parameter — adds `torusConsistency` as 6th sub-metric (15% weight when available, redistributes other weights)
- ALL new Codable fields are Optional with nil defaults — backward compatible

### Nocebo/Reflexivity Rules
- **No negative predictions** — coaching messages must predict positive actions, not negative outcomes
- **No deterministic harm language** — "can help" not "will reduce", "consider" not "expect"
- **Always include reversibility** — "this can improve within days" not "your rhythm is destabilized"
- **Labels are growth-oriented** — "Building" not "Disorganized", "Room to grow" not "Weak rhythm"
- **Health claims need context** — no unqualified "metabolic risk", always pair with actionable advice
- See `docs/superpowers/specs/COACH_REVIEW.md` for the full audit guide

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

### Sleep Path Gradient (CRITICAL — physiological direction)
- **Fade IN at start, SHARP cut at end**. Falling asleep is gradual (we don't notice). Waking up is abrupt. Visual must match.
- Per-segment blend: first 20% of each sleep run mixes `prevColor → baseColor`. Remaining 80% stays solid `baseColor`.
- `capStart` color = `prevColor` (so the start circle matches the fade-in). `capEnd` color = `baseColor` (sharp — the amber live-awake extension takes over cleanly).
- The opposite direction (fade at end toward `nextColor`) was removed 2026-04 — it contradicted the physiology metaphor.

### Cursor Movement (verified 2026-04)
- **No forward cap** — `cursorAbsHour` must NEVER be clamped to `Double(maxDays) * period`. The spiral extends dynamically via `maxReachedTurns`.
- Three gesture handlers in `SpiralModeView.swift` previously had `min(maxHours, ...)` — all removed. Only the lower bound `max(0, ...)` stays.
- `nearestHour(totalHours:)` uses `max(maxReachedTurns + 1, numDays) * period` as search bound — enough to catch future arm taps without re-introducing a hard cap.

### Data Points (drawDataPoints)
- **No isLastRecord exceptions** — all records treated equally
- **No skipEdge** — no edge fade applied
- Records filtered by: `vis.isVisible` (always true) + `isBehindCamera` + `perspectiveScale > 0.04`
- Tap info: `showInfoForCursorPosition()` uses `cursorAbsHour` (absolute hours) to compare against bed/wake ranges. Guard `inSleepRange` BEFORE checking phases. Shows specific phase: Deep sleep, Light sleep, REM (dreams), Brief awakening.

## HealthKit Sync Rules (CRITICAL)

### Sync Architecture
- **3 parallel mechanisms**: HKObserverQuery (debounced 500ms) + HKAnchoredObjectQuery (direct callback) + foreground polling
- **Background delivery** — `enableBackgroundDeliveryWithRetry(attempts: 3)` with 1s between retries
- **Anchored query** — persisted anchor in UserDefaults, resumes from last position on relaunch
- **Incremental fetch** — `fetchRecentNewEpisodes()` searches **7 days** (not 3), deduplicates by healthKitSampleID

### Foreground Return Flow
1. Immediate fetch (7 days)
2. If empty: retry ladder **[5, 15, 30, 60]** seconds (110s total)
3. Fast polls: **6 × 10s** = 60s of aggressive polling
4. Slow polls: **every 60s** while app stays active
5. All polling cancelled on `didEnterBackgroundNotification`
6. `isSyncingHealthKit` flag shows "Updating..." indicator in SpiralTab

### Pitfalls to Avoid
1. Never assume HealthKit has Watch data immediately — Watch→iPhone BT sync can take 1-2 minutes
2. Never do a single fetch without retries — always use the retry ladder
3. Never log health data in production — all prints must be `#if DEBUG`
4. Never modify the anchor persistence — `sleepAnchor` setter auto-persists to UserDefaults
5. The `isImporting` flag prevents race conditions during `importAndAdjustEpoch()` — respect it

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

## SleepDNA Pipeline Rules (CRITICAL — updated 2026-04)

### Tier Thresholds (LOWERED from 4/8 to 2/4 weeks)
- `basic`        — `dataWeeks < 2`  (records.count < 14). Encoding only, no motifs, no mutations, no predictions.
- `intermediate` — `dataWeeks in 2..<4`. **Motifs + mutations + predictions + Poisson run here.**
- `full`         — `dataWeeks >= 4`. Adds BLOSUM learning, Hawkes, persistent homology, linking number, mutual info spectrum.

### Motif / Mutation Gates
- Motifs run when `tier != .basic` (i.e. >= 2 weeks). NOT gated to `.full` anymore.
- Mutations run when `tier != .basic && !motifs.isEmpty`.
- **`MotifDiscovery.minimumSequences = 4`** (10 records). This is the real algorithmic floor. The tier gate MUST NOT be stricter than this.
- Default DTW threshold: **2.0** (not 8.0). With normalized [0,1] features, 8.0 merges everything into one cluster.

### Schema Version Invalidation (CRITICAL)
- `SleepDNAService.schemaVersion: Int` is persisted in `UserDefaults.standard` key `"dna.schema.version"`.
- **BUMP the version whenever the pipeline semantics change** (tier gates, motif thresholds, new fields on `SleepDNAProfile`). Otherwise users keep seeing stale cached snapshots indefinitely.
- History: `v1` original 8-week gate · `v2` lowered to 2 weeks · `v3` added `motifDiagnostics` field.
- `refreshIfNeeded` short-circuits on "today already computed" ONLY when the stored schema version matches. A mismatch forces a recompute regardless.

### DNAModeView must trigger refreshIfNeeded
- **Bug that hit us**: `DNAInsightsView` was the only caller of `refreshIfNeeded`. Users on the main DNA tab never got their cache invalidated after schema bumps.
- Fix: DNAModeView has `.task(id: isActive) { await dnaService.refreshIfNeeded(store:context:) }`. Any new tab that surfaces DNA content must do the same.

### MotifDiagnostics (empty-state UX)
- `MotifDiscovery.discoverWithDiagnostics` returns motifs + `MotifDiagnostics` (sequencesAnalyzed, clustersFormed, multiMemberClusters, min/med/max DTW distance, threshold).
- Populated on every run regardless of motifs outcome. Exposed via `profile.motifDiagnostics` (Optional, Codable-backward-compat).
- UI (Patterns empty sheet) shows the collapsible "Diagnóstico" panel with these numbers + human hint:
  - `sequencesAnalyzed < 4` → "not enough data"
  - `multiMemberClusters == 0 && maxDistance < threshold * 0.5` → "too similar"
  - `multiMemberClusters == 0 && minDistance > threshold` → "too varied"
  - else → "borderline"
- Also `[MOTIF]` DEBUG print for Xcode console.

### Motif Name Localization
- Engine produces English names ("Early-bird", "Late-wakeup", etc). **ALWAYS** pipe through `localizedMotifName(_:)` which looks up `dna.motif.name.<lower-name>` in xcstrings.
- If you add a new code site that shows a motif name — card chips, timeline lanes, etc — verify it uses the helper, not raw `motif.name`.
- Pattern legend sheet (`patternsHelpSheet`) documents what each of the 28 motif names means; update its `motifNameCatalog` when adding a new auto-name pair.

### Pitfalls to Avoid
1. Never re-gate motifs behind `tier == .full`. The floor is `tier != .basic`.
2. Never skip the schema version bump when changing pipeline semantics.
3. Never call `Text(motif.name)` directly in UI — always `localizedMotifName(motif.name)`.
4. Never expect `refreshIfNeeded` to fire from sheets alone — the tab that displays DNA cards must trigger it.
5. Never remove `motifDiagnostics` from `SleepDNAProfile` — UI depends on it for the empty state.

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
- **`nowTurns` clips data to current time** — `SpiralEntry.nowTurns` calculated from `Date.now` in re-based coordinates. `drawDataPoints` clips phases past `nowTurns` so the last record doesn't fill to midnight. Live awake extension draws from data end to `nowTurns`.
- **Live awake extension** — amber path from `dataEndTurns` to `nowTurns`, grows progressively as timeline refreshes (every 30 min)

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
6. Never draw phases past `nowTurns` — clips to current time, prevents amber path extending to midnight

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

### Cursor & Live Awake Extension
- **Cursor starts at current time** (now), NOT at end of sleep data
- **Live awake extension** — amber path from end of data to cursor, grows with time (same as iPhone)
- `store.currentAbsoluteHour` gives the current wall-clock position

### Backbone
- **Backbone extends from turn 0 to midnight (00:00) of the cursor's current day** — NOT to cursor position, NOT to extentTurns
- When cursor crosses to a new day, backbone grows to that day's midnight
- Formula: `backboneTo = Double(Int(floor(cursorAbsHour / period)) + 1)`

### Opacity & Fade
- **Bidirectional fade** — data outside the 4-day window fades smoothly on BOTH sides (past AND future)
- `geo.opacity(turns:)` returns 1.0 inside window, fades to 0 over 1.5 turns outside
- **All draw functions must use `geo.opacity(turns:)`** — backbone, data arcs, events, caps
- renderFrom/renderUpTo extend 1.5 turns beyond the window for fade margin

### Pitfalls to Avoid
1. Never use perspective projection (Cam/focalLen/zStep) on Watch — always flat
2. Never show all data at once — Watch screen too small, use windowed view (~4 days) with fade
3. Never allow negative radius — clamp with `max(0, ...)` or turns before window produce mirror spirals
4. Never use thin line widths (<3pt) on Watch — illegible on small screen
5. Never store Watch spiral settings (depthScale/spiralType) from iPhone sync — Watch is always flat archimedean
6. Never hard-cut data at window edges — always fade smoothly (opacity gradient over 1.5 turns)
7. Never position cursor at end of sleep data — always at current time (now)
8. Never extend backbone past midnight of cursor's day — it should grow day-by-day, not continuously

## Watch 3D Torus Rules (CRITICAL)

### Architecture
- **SceneKit** — `SleepTorusScene.swift` (scene) + `SleepTorusView.swift` (SwiftUI wrapper) + `TorusGeometry.swift` (math)
- **Torus R=1.8, r=0.6** — wireframe + solid back-face + rim light, camera distance 9.5
- **Trajectory** — sleep epochs → phi via `phiMap` (W=0.05, N2=0.55, REM=0.62, N3=0.85 × 2π), theta linear × 4.5 turns, `maxPhiStep=0.12` (no teleporting)

### Interactions
- **Playing**: Crown rotates camera, tap pauses, swipe changes tab
- **Paused**: Crown scrubs timeline, drag rotates camera (overlay with `allowsHitTesting(isPaused)`), tap resumes
- **Haptic**: `WKInterfaceDevice.current().play(.click)` on stage transitions

### Battery (CRITICAL)
- **Lazy animation** — `init()` does NOT call `startAnimation()`. `.task{}` starts it, `.onDisappear` stops it
- **`torusParent.isPaused`** — stops SCNAction auto-rotation when not visible
- **Timer 10fps** (0.1s) — sufficient for Watch, not 20fps
- **HealthKit**: only anchored query (not both observer + anchored), debounce 30s between refreshes

### Pitfalls to Avoid
1. Never start animation in `init()` — drains battery from app launch even on invisible tabs
2. Never use both `startObservingNewSleep()` + `startAnchoredSleepQuery()` — doubles callbacks
3. Never use `minimumDistance: 0` on drag gesture — blocks TabView page swiping
4. Never attach drag gesture unconditionally — use `allowsHitTesting(isPaused)` overlay

## Coach Tab Rules (REDESIGNED 2026-04 — editorial bento)

The honeycomb hexagonal grid is gone. Coach tab is now an editorial scroll with
hero bento cards (`CoachHomeView`, `CoachBentoGrid`, `CoachDataAdapter`).

### Architecture
- `CoachDataAdapter` — pure read-only struct that derives display data from `SpiralStore`.
  Internal helpers are `internal` for testability (`lastNBedtimeLatenessNorm`, `normalizeBars`,
  `sriLabel`, `formatHour`, `chronotypeLabelEs`). Tests in `spiral journey projectTests/CoachDataAdapterFormattingTests.swift`.
- `CoachHomeView` renders the hero bento + proposal + change story + learn CTA.
- Coach tab never renders hexagonal bubbles. DO NOT re-introduce `CoachBubbleEngine` or
  `HoneycombLayout` — those files are obsolete.

### Insight Title Localization
- `CoachEngine.coachInsight` emits English fallback titles + stable `issueKey`.
- `CoachDataAdapter.localizedInsightTitle()` resolves `coach.issue.<issueKey>.title` via
  `Bundle.main.localizedString`. Falls back to the English title if the key is missing.
- Never surface `insight.title` raw in the UI — always pipe through the adapter.

## macOS Compatibility Rules (CRITICAL)

### Platform Guards
- **`navigationBarTitleDisplayMode`** → `#if !os(macOS)` always
- **`topBarLeading` / `topBarTrailing`** → use `.cancellationAction` / `.confirmationAction` (cross-platform)
- **`UIKit`** → `#if canImport(UIKit)` with `#elseif canImport(AppKit)` where needed
- **`UIColor`** → use `SCNPlatformColor` typealias (`UIColor` on iOS, `NSColor` on macOS) for SceneKit files
- **`CADisplayLink`** → Timer fallback on macOS (`#if os(macOS)`)
- **`BGTaskScheduler`** → entire `BackgroundTaskManager` wrapped in `#if !os(macOS)`
- **`UNUserNotificationCenter.delegate`** → `#if !os(macOS)`
- **`@available(iOS 26, *)`** → add `macOS 26` when using Foundation Models
- **`ShareSheet`** → `#if os(iOS)` only

### macOS Drag Overlay
- SpiralTab uses a transparent overlay for mouse drag → cursor movement
- **`minimumDistance: 5`** (not 0) — lets clicks pass through to buttons
- Covers spiral area only, not the action bar zone

### Manual Sleep Entry on Mac
- `store.addManualEpisode()` — persists to SwiftData + in-memory + recompute. Always use this, not raw `sleepEpisodes.append`
- **Cursor reset bug** — `.onChange(of: sleepEpisodes.count)` must NOT reset `cursorAbsHour` on manual entry. Only reset on first import (`wasEmpty`)
- `LongPressGesture` disabled on macOS (`#if !os(macOS)`) — interferes with mouse clicks

## Code Quality Rules

### Logging
- **All print() statements MUST be wrapped in `#if DEBUG`** — production logs must not leak sleep data, dates, or personal info
- Applies to: SpiralStore, HealthKitManager, WatchHealthKitManager, WatchConnectivityManager

### Color Consistency
- **Always use `SpiralColors` semantic colors** — `SpiralColors.good`, `.moderate`, `.poor`, `.muted` in View files
- **Never hardcode hex** for good/moderate/poor in Views — `Color(hex: "5bffa8")` doesn't adapt to light mode, `SpiralColors.good` does (dark `#5bffa8`, light `#198752`)
- **Sleep phase colors** — use `SpiralColors.deepSleep`, `.remSleep`, `.lightSleep`, `.awakeSleep` (theme-aware)
- **Model `.hexColor` is OK** — `Color(hex: event.type.hexColor)` converting from model data is acceptable; these are data-driven, not semantic
- **Watch exception** — `WatchColors.swift` has its own palette (no asset catalog on watchOS)

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


## Natural Sleep Model (Validated Research — March 2026)

### Core Change: 3 Natural States, NOT 5 AASM Stages

The app should represent sleep as the geometry reveals it, not as AASM conventions dictate.

**AASM (artificial, convention-based):**
```
W → N1 → N2 → N3 → REM  (5 discrete categories)
```

**Natural (validated with 142 + 13 subjects across 2 datasets):**
```
Pole 1 (Active):  Wake, REM, N1  — geometrically identical (< 3.5° apart)
Pole 2 (Deep):    N2, N3         — geometrically identical (~12-14° apart)
Between poles:    continuous depth gradient (NOT discrete steps)
```

### What This Means for the App

1. **3 colors, not 5** — Wake (one color), NREM depth gradient (continuous color ramp from light to deep), REM (distinct color)
2. **Depth score instead of stages** — ω₁ (winding number) provides a continuous 0-1 depth metric. Lower ω₁ = deeper sleep. No arbitrary N1/N2/N3 boundaries.
3. **REM is NOT "between" N2 and Wake** — REM is geometrically almost identical to Wake (< 3° apart). It's Wake with muscles disconnected. Display it near Wake, not between sleep stages.
4. **N1 is NOT a sleep stage** — it's the transition from Wake to NREM. Display it as the beginning of the depth gradient, not as a separate category.

### Validated Numbers (use for depth mapping)

```
ω₁ by stage (HMC, 142 subjects, 117K epochs):
  N3:   lowest  (deepest sleep)
  N2:   low
  REM:  medium  (but geometrically at active pole)
  N1:   high    (transition)
  Wake: highest (most active)

Two geometric poles confirmed in:
  HMC (142 subjects, C4-M1 electrode):  W-REM = 2.6°, N2-N3 = 11.5°
  Sleep-EDF (13 recordings, Fpz-Cz):    W-REM = 1.7°, N2-N3 = 13.7°
  Structure is universal. Angle between poles varies by electrode location.
```

### HealthKit Mapping

Apple HealthKit reports: `.asleepCore` (N1+N2), `.asleepDeep` (N3), `.asleepREM`, `.awake`

Map to natural model:
```swift
// HealthKit → Natural Sleep Model
.awake       → Wake (active pole)
.asleepREM   → REM (active pole, muscles disconnected)
.asleepCore  → NREM light-to-moderate (depth gradient 0.3-0.6)
.asleepDeep  → NREM deep (depth gradient 0.7-1.0)
```

The depth gradient is continuous — `.asleepCore` and `.asleepDeep` are just Apple's coarse bins of the same continuum. If raw HR/HRV data is available, compute ω₁ for finer depth resolution.

### Phase A Multimodal Findings (for future features)

If Watch raw PPG/HR becomes available:
- ECG raw torus works for sleep classification (κ=0.449 with 41 subjects)
- Combined EEG+ECG gives κ=0.502 (better than EEG alone)
- Heart and brain see REM differently: brain says "active", heart says "like N2"
  This is statistically confirmed: Wilcoxon p = 8.68×10⁻¹⁵ with 135 subjects
- REM has the HIGHEST brain-heart coupling (not lowest, contradicts prior assumptions)
- EEG-EMG pair is most informative for sleep staging (κ=0.436)

### What NOT to Do
- Do NOT show N1, N2, N3 as separate colored bands
- Do NOT treat REM as "between" NREM and Wake
- Do NOT use 5-color schemes matching AASM conventions
- Do NOT impose discrete boundaries on the depth gradient
- DO show Wake and REM near each other visually
- DO show NREM as a smooth color gradient from light to deep
- DO use ω₁ or depth score as the primary metric, not stage labels

## Simulator & Mock Data Rules (CRITICAL — updated 2026-04)

- `SpiralStore.init` has two `#if targetEnvironment(simulator)` blocks. Both are
  gated behind **`ENABLE_MOCK_DATA=1`** environment variable (Xcode → Scheme →
  Run → Environment Variables).
- **Default simulator behavior is now real-device-like**: persistent
  UserDefaults + empty `sleepEpisodes` on first launch. Onboarding flow runs,
  welcome screen shows, chronotype questionnaire appears, tutorial works.
- **Enable mock data only for App Store screenshots**. The mock flow wipes
  UserDefaults on every launch, injects 10 weeks of episodes from
  `MockDataGenerator`, and marks `hasCompletedOnboarding = true`.
- **Never flip the semantics back to opt-out** (the previous `SKIP_MOCK_DATA=1`
  approach). Opt-in is the correct default because the common case for a
  developer running the simulator is "test the actual flow".

## Chronotype Icon Rules

- **Use `Chronotype.sfSymbol`, NOT `.emoji`, in UI**.
  Mapping: `sunrise.fill` / `sun.max.fill` / `cloud.sun.fill` / `moon.fill` / `moon.stars.fill`.
- Rendered via `Image(systemName:)` with `.symbolRenderingMode(.hierarchical)` and
  `.foregroundStyle(SpiralColors.accent)`.
- The `.emoji` property still exists (with `\u{FE0F}` VS16 on dual-use code points)
  for places that genuinely need a text glyph, but prefer SF Symbols everywhere
  — emojis can render as "tofu boxes" depending on font context (particularly
  `U+26C5` cloud-sun).

## Tutorial / Onboarding Rules

- `OnboardingFrames` carries `CGRect`s for each target (spiralArea, moonButton,
  eventsBtn, tabBar, cursorBar). Views attach `.reportFrame(\.targetName)` to
  publish their real geometry.
- **If you move a button, update its `.reportFrame` call at the new location**
  AND update the matching fallback coordinates in
  `OnboardingOverlayView.highlight(for:screenSize:)`. The fallback only kicks
  in when no frame has been reported yet (first frame of the overlay).
- Current anchors:
  - `.moonButton` = bottom-center log button (64 pt) in SpiralModeView action bar.
  - `.eventsBtn`  = top-right `+`/moon/eye button in SpiralModeView floating header.
- Tooltip direction: `tooltipBelow: true` + `arrowDirection: .up` when the
  tooltip sits BELOW the highlight; `tooltipBelow: false` + `arrowDirection: .down`
  when it sits ABOVE. Get these in sync or the arrow points away from the target.
