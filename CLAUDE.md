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

### Camera
- Camera follows cursor: `camFrom = max(focus - span, 0)`, `camUpTo = focus + 0.5`
- **NEVER add camera reach-back** to stretch camera toward distant data. This compresses the spiral.
- Zoom capped at 7.0 turns max (`maxZoomOutTurns`), min 0.08 turns

### Perspective
- All draw functions MUST skip segments with `perspectiveScale < 0.10` (data, caps, rings)
- This prevents blobs at spiral center when data is far from camera
- Do NOT raise threshold above 0.10 — cuts visible days in normal view

### Draw Order
- Awake data → live awake extension → sleep data (sleep always on top)
- Live awake extension starts from `max(cutTurns, tWakeRaw)`, never from wakeupHour alone

### Visibility
- Edge fade per-segment at camera boundary (margin 1.5 turns)
- Opacity by distance from cursor (opacityCurve 7 entries + exponential decay)
- Context blocks only behind cursor (`dayIndex <= requestedActiveIndex`)

### Pitfalls to Avoid
1. Never force camera to include distant data — causes compression
2. Never use min lineWidth without perspScale guard — creates blobs
3. Never draw live awake extension from wakeupHour — hides sleep data
4. Never show context blocks ahead of cursor
5. Never allow unlimited zoom-out to maxReachedTurns
