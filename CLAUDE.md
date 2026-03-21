# Spiral Journey Project

## Build
- iOS: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
- Watch: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS`

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
