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

### Sliding Window Camera System
- **Cursor moves freely** — past and future, no limits on movement
- **Window = [cursor - span, cursor + 0.5]** — only content within this window is rendered
- **7 days visible** — opacityCurve gives full opacity to 7 days, then 0
- **No opacity fade** — days inside window are 100%, outside are 0%. The path "shortens" progressively as cursor advances (segmentEdgeFade at the old edge, 1.5 turns of transition)
- **Zoom auto-adjusts** — `autoFitScale` in CameraState ensures nothing projects beyond 85% of canvas. Calculated by scanning all visible turns and scaling proportionally.
- **User can still pinch-zoom** — changes `span` (visible turns), auto-fit corrects if needed

### Camera (CameraState)
- `tRef = upToTurns + 0.5` — depth reference point
- `camZ = margin * zStep - focalLen` — camera position (fixed formula)
- `focalLen = maxRadius * 1.6` (3D) or `maxRadius * 1.2` (flat) — 3D has closer initial zoom
- `autoFitScale` — computed per-frame: scans all visible turns, finds max projected radius, scales so it fits in 85% of canvas. 1.0 when everything fits, < 1.0 when too large.
- Applied in `project()` and `perspectiveScale()` — both position and linewidth scale together

### Visibility (SpiralVisibilityEngine)
- **Single distance source** — `abs(requestedActiveIndex - dayIndex)`. NO dual distance (effectiveActiveIndex was removed — it caused non-monotonic fade)
- `opacityCurve = [1.0 × 7]` — 7 days at full opacity
- `dist >= 7` → opacity = 0.0 (hard cut, no exponential decay)
- `segmentEdgeFade` — 1.5 turns of gradual transition at the old edge of the window. Per-segment, not per-day.
- Context blocks only behind cursor (`dayIndex <= requestedActiveIndex`)

### Draw Order
- Awake data → sleep data (sleep always on top)
- **Live awake extension** — drawn OUTSIDE the record loop, always extends from data end to cursor position. Not gated by day visibility. This is the vigilia path that grows with the cursor.
- Live awake extension starts from `max(dataEndTurns, tWakeRaw)`, never from wakeupHour alone

### Data Points (drawDataPoints)
- **No isLastRecord exceptions** — all records treated equally
- **No skipEdge** — all records apply edge fade equally
- Records filtered by: window bounds + `vis.isVisible`
- Per-segment: `isBehindCamera` + `perspectiveScale > 0.04` checks

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
1. Never force camera to include distant data — causes compression
2. Never use min lineWidth without perspScale guard — creates blobs
3. Never draw live awake extension from wakeupHour — hides sleep data
4. Never show context blocks ahead of cursor
5. Never allow unlimited zoom-out to maxReachedTurns
6. Never pass `maxReachedTurns` directly as `spiralExtentTurns` for logarithmic spirals — use `effectiveSpiralExtent`
7. Never assume `store.depthScale` is 1.5 — default is **0.15**
8. Never enable `linkGrowthToTau` for logarithmic spirals with period=24 — growthRate becomes 0
9. Never use dual-distance opacity (effectiveActiveIndex + requestedActiveIndex) — causes non-monotonic fade
10. Never add isLastRecord exceptions to drawDataPoints — creates fragments when cursor moves to future
11. Never let tRef grow unbounded with cursor — autoFitScale handles the zoom adaptation instead
