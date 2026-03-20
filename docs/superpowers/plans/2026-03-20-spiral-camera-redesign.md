# Spiral Camera Redesign — Implementation Plan

## Context

The current spiral rendering system has accumulated patches that create bugs: fragments at the spiral center, wrong fade order (day 28 fades before day 27), zoom not adapting when cursor goes to future days. The root cause is that visibility, opacity, and clipping are spread across multiple layered systems (opacityCurve, edgeFade, segmentEdgeFade, perspectiveScale, isBehindCamera, isLastRecord exceptions) that interact unpredictably.

## Goal

A clean sliding window where:
1. Cursor moves freely (past/future, no limits)
2. Only the 7 days behind the cursor are visible
3. The OLDEST day in the window fades first (monotonic from cursor outward)
4. Vigilia path extends with cursor into future
5. Zoom auto-adjusts + user can pinch
6. Works identically for all geometries (archimedean 2D/3D, log 2D/3D)
7. Preserve all visual values (colors, line widths, phase rendering)

## Root Cause Analysis

The bug where day 28 disappears before day 27 happens because:

1. `visibilityState()` uses TWO distance calculations: one from `effectiveActiveIndex` (clamped to data) and one from `requestedActiveIndex` (actual cursor). These can disagree, causing non-monotonic opacity.

2. `effectiveActiveIndex` clamps to `lastDayIndex` when cursor goes past data. So if cursor is at day 15 but data only goes to day 8, `effectiveActiveIndex = 8`. Days near 8 get high opacity (distance 0 from effective) but days near 15 get LOW opacity (distance 7 from effective, but distance 0 from requested). This creates a "hole" where middle days are dimmer than edge days.

## The Fix: Single Distance Source

**Replace the dual-distance opacity with a SINGLE distance: from the cursor (requestedActiveIndex).** Period. No clamping to data, no effective index. The cursor IS the reference.

## Detailed Changes

### File 1: `SpiralVisibilityEngine.swift`

#### Change 1: Simplify `visibilityState()` (Lines 365-411)

**Current (broken):**
- Computes `dist = abs(effectiveActiveIndex - dayIndex)` → rawOpacity from curve
- Computes `cursorDist = abs(requestedActiveIndex - dayIndex)` → cursorFade multiplier
- Final = rawOpacity × cursorFade (two sources → non-monotonic)

**New (clean):**
```swift
static func visibilityState(for dayIndex: Int, window: VisibleDayWindow) -> DayVisibilityState {
    // Single distance: from the actual cursor position
    let dist = abs(window.requestedActiveIndex - dayIndex)

    let rawOpacity: Double
    if dist < opacityCurve.count {
        rawOpacity = opacityCurve[dist]
    } else {
        let base = opacityCurve.last ?? 0.05
        let extra = dist - opacityCurve.count + 1
        rawOpacity = base * pow(0.15, Double(extra))
    }

    let blur = dist < blurCurve.count ? blurCurve[dist] : (blurCurve.last ?? 2.0)
    let strokeScale = dist < strokeScaleCurve.count ? strokeScaleCurve[dist] : (strokeScaleCurve.last ?? 0.58)

    return DayVisibilityState(
        isVisible: rawOpacity > 0.01,
        opacity: rawOpacity,
        emphasis: rawOpacity,
        blur: blur,
        strokeScale: strokeScale,
        distanceFromActive: dist
    )
}
```

This guarantees MONOTONIC fade: day closest to cursor = brightest, day furthest = dimmest. Always. No exceptions.

#### Change 2: Update opacityCurve

**Current:** `[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.4, 0.05]`

This is fine — 6 days full, day 7 fades. Keep it.

### File 2: `SpiralView.swift`

#### Change 3: Clean drawSpiral() camera (Lines 244-287)

**Keep the sliding window camera as-is** (my last change was correct):
```swift
let windowFrom = max(focusTurns - span, 0)
let windowUpTo = focusTurns + cameraFrontPadding
```

This is correct. renderFrom = windowFrom, renderUpTo = windowUpTo.

#### Change 4: drawDataPoints() — remove ALL exceptions (Lines 640-858)

**Remove:**
- `isLastRecord` forced rendering (already removed)
- `isLastRecord` skip edge fade
- 3D perspective check at record level (midScale > 0.12) — unnecessary if visibility is correct
- Debug logs

**Keep:**
- Per-segment `segmentEdgeFade` at camera boundary
- Per-segment `isBehindCamera` and `perspectiveScale > 0.04` check
- Phase color rendering, line widths, draw order

**Live awake extension:** Keep drawing for `isLastRecord` WITHOUT `vis.isVisible` gate — the vigilia path always extends to cursor.

#### Change 5: drawSpiralPath() backbone — use renderFrom (already done)

`backboneFrom = max(state.renderFromTurns, 0)` — correct, keep.

#### Change 6: Remove all centerDist culling

The `centerDist < threshold` checks in drawSpiralPath are unnecessary with proper visibility. Remove them — they cause more problems than they solve.

### File 3: `SpiralTab.swift`

#### Change 7: Remove cursor padding limit

**Current:** `let cursorPadding = 1.5` — limits how far cursor can go past data.

**New:** Remove this limit. The cursor should move freely. The visibility system handles what's shown.

```swift
let searchMax = Double(maxDays) * store.period  // full range, no padding limit
```

### Verification Checklist

After each change, test:

- [ ] Archimedean 2D: cursor to future → no fragment at center
- [ ] Archimedean 3D: cursor to future → no fragment at center
- [ ] Log 2D: cursor to future → no fragment
- [ ] Log 3D: cursor to future → no fragment, zoom OK
- [ ] All modes: days fade in correct order (oldest first, monotonic)
- [ ] All modes: vigilia path extends with cursor
- [ ] All modes: pinch zoom works
- [ ] All modes: cursor to past → data stays visible
- [ ] Edge case: only 1 day of data → renders correctly
- [ ] Edge case: cursor at present (normal use) → no regression
