# Tri-Modal Sleep Viewer — Design Spec

## Overview

Redesign SpiralTab as a unified tri-modal sleep viewer: **Torus** (past/last night), **Spiral** (present/chronobiograph), **DNA** (future/patterns). Modes are navigated via horizontal swipe (TabView pager) or pills selector. Integrates ClaudiaApp research advances (8 toroidal features, pythagorean equation, cross-domain validation).

## Architecture

```
SpiralTab (container)
├── Fixed: Header contextual (crossfade on mode change)
├── Fixed: Pills selector [🍩 Torus · 🌀 Spiral · 🧬 DNA]
├── Pager: TabView(.page), 3 pages
│   ├── Page 0: TorusModeView
│   ├── Page 1: SpiralModeView (current SpiralTab content extracted)
│   └── Page 2: DNAModeView
└── Global overlays: undo toast, sync indicator
```

### Fixed Elements (don't swipe)
- App tab bar (Spiral/Tendencias/Coach/Ajustes)
- Header text — contextual per mode, crossfade animation
- Pills selector — synced with pager index

### Sliding Elements (swipe with content)
- Main content area
- Action bar (3 buttons, same visual position per mode)

### Default Mode
Spiral (page 1, center of pager). User swipes left→Torus or right→DNA.

### Gesture Conflict Resolution
- Pager swipe: handled by TabView default gesture recognition
- Torus drag rotation: `minimumDistance: 15` on the drag prevents triggering pager swipe
- DNA scroll: vertical ScrollView doesn't conflict with horizontal pager

## Mode 0: Torus (Past — Last Night)

### Content
- **SceneKit** 3D torus with transparent background (`scene.background.contents = UIColor.clear`)
- Based on Watch `SleepTorusScene.swift`, adapted for iPhone (larger screen, higher resolution trail, finer wireframe)
- Torus R=1.8, r=0.6 (same geometry as Watch)
- Trajectory of last night with animated trail (colored by phase)
- Glowing dot + halo tracking position on torus
- Label overlay (capsule): "Deep · 02:34" (phase + time)
- Drag gesture rotates torus freely
- No 4D slider — simplified interaction
- Haptic click on phase transitions

### Action Bar
| Left | Center | Right |
|------|--------|-------|
| ⏪ Rewind (jump to prev phase) | ▶️/⏸ Play/Pause | ⏩ Forward (jump to next phase) |

- **Rewind/Forward are continuous, not jumps**: while held, trajectory scrubs smoothly at 60fps with trail visible. Releasing stops the scrub. Works even when paused — holding rewind/forward moves the trajectory, releasing freezes it again.
- Play: trajectory advances automatically with progressive trail
- Pause: frozen, label visible. Rewind/forward still work (scrub while paused).

### Header
"Anoche · {duration}h · Estabilidad {stability}%"

### Data Source
- Last `SleepRecord` from store
- `SleepTrajectoryAnalysis` from SpiralGeometry for toroidal trajectory
- `TorusGeometry` for torus surface mapping

### iOS Compatibility
- SceneKit works from iOS 17.0 (no @available gates needed)
- Replaces current RealityKit-based `NeuroSpiralTorus3DView` (`@available(iOS 18.0, *)`)

## Mode 1: Spiral (Present — Chronobiograph)

### Content
- Extracted from current `SpiralTab.swift` into `SpiralModeView.swift`
- All existing functionality preserved: Canvas spiral, cursor, zoom, gestures, data rendering, live awake extension, info panel on tap
- No behavioral changes — pure extraction

### Action Bar
| Left | Center | Right |
|------|--------|-------|
| 📊 Stats | 🌙/☀️ Log sleep (+ spinner + undo toast) | 💡 Coach tip |

- Identical to current SpiralTab action bar

### Header
"Buenas noches, Carlos" (or contextual coach greeting)

## Mode 2: DNA (Future — Patterns & Predictions)

### Content
Vertical ScrollView of cards reorganizing existing DNA views:

| Card | Size | Content | Interaction |
|------|------|---------|-------------|
| Patrones detectados (motifs) | Compact | Mini-summary of recurring patterns | Tap → sheet |
| Mutaciones | Compact | Silent/missense/nonsense counts | Tap → sheet |
| Triángulo de sueño | Large inline | Full `SleepTriangleView` embedded | Visible directly |
| Hélice 3D | Compact preview | Mini 3D helix preview | Tap → fullscreen |
| Historial sparklines | Large inline | `NeuroSpiralHistoryView` sparklines | Visible directly |
| Salud circadiana | Large inline | Health markers as gauges/bars | Visible directly |
| Predicción | Compact | Tonight's prediction summary | Tap → sheet |
| Export CSV | Compact button | Export icon | Tap → ShareSheet |

### Card Design Philosophy
- **Visual > text**: futuristic minimalist, communicate through geometry, animation, and color
- **Tooltips**: long-press on any card shows one-line explanation (not a full sheet)
- **Info fallback**: ℹ️ button somewhere accessible opens educational sheet (existing DNAInfoSheetView) — to be removed in the future when UI is self-explanatory

### Action Bar
| Left | Center | Right |
|------|--------|-------|
| 🔗 Patterns (animated arrows on helix) | 🧬 Analyze | 📊 Mutations / Range |

- **Analyze** (center): triggers recompute of DNA analysis. Left/right buttons disabled until analysis completes.
- **Patterns** (left): activates animated arrows/arcs on the helix 3D (visible in the helix card or fullscreen) connecting related temporal patterns — luminous arcs between helix bars that share the same motif.
- **Right**: mutations overlay or temporal range selector (7d/14d/30d)

### Header
Contextual insight: "Tu patrón semanal mejora" / "3 patrones detectados" / etc.

## Experimental: 8 Toroidal Features

### Purpose
Internal/experimental measurement to validate if geometric state correlates with user's real state. NOT visible to the user as UI elements.

### The 8 Features (from ClaudiaApp)
1. **ω₁**: angular velocity in θ (homeostatic pressure)
2. **ω₂**: angular velocity in φ (circadian rhythm)
3. **omega_ratio**: arctan2(ω₁, ω₂) (balance)
4. **θ_dispersion**: angular spread in θ (variability)
5. **φ_dispersion**: angular spread in φ
6. **residence_fraction**: time at dominant vertex (focus)
7. **stability_score**: entropy of vertex occupation
8. **torus_deviation**: distance from ideal torus surface

### Implementation
- Computed from `SleepTrajectoryAnalysis` (most already exist: ω₁, ω₂, stability)
- Add missing features: dispersions, residence_fraction, torus_deviation
- Store in `SleepTrajectoryAnalysis` struct
- Log to console in DEBUG for comparison with user's subjective state
- Future: add optional "How do you feel?" prompt to collect ground truth

## Research Integration

### Pythagorean Equation
- `ratio = 1/√[(1-β)² + (γ/d)²]`
- Compute β from user's winding ratio data
- Verify predicted vs actual ratio
- Surface in DNA card "Salud circadiana" as a geometric coherence metric

### Genomic Narrative
- Enrich educational content (DNAInfoSheetView) with validated cross-domain findings
- "The same torus that reads your sleep can detect patterns in DNA sequences (AUC 0.748)"
- Strengthens the SleepDNA metaphor with real evidence

### Cross-Domain Validation
- Mention in educational section: torus outperforms PCA in 14/14 domains
- Sleep: κ=0.606 vs 0.264 (2.3x ratio)

## File Changes

### New Files
- `TorusModeView.swift` — Torus mode container
- `SleepTorusSceneiPhone.swift` — SceneKit scene adapted from Watch
- `SpiralModeView.swift` — Extracted from SpiralTab
- `DNAModeView.swift` — DNA cards container
- `DNACard.swift` — Reusable card component (compact/large variants)
- `ModeHeaderView.swift` — Contextual header with crossfade
- `ModePillsView.swift` — Pills selector component

### Refactored Files
- `SpiralTab.swift` — Becomes thin container (pager + fixed elements)
- `NeuroSpiralView.swift` — Content redistributed into DNA cards
- `SleepTrajectoryAnalysis` — Extended with 3 new toroidal features

### Preserved (reused as card content)
- `SleepTriangleView.swift` — Embedded in large inline card
- `NeuroSpiralHistoryView.swift` — Embedded in large inline card
- `NeuroSpiralExportView.swift` — Simplified as export button card
- `HelixSceneBuilder.swift` + `Helix3DView` — Used in compact preview + fullscreen

## Transition Animations
- **Mode switch**: TabView(.page) native swipe + pills sync via `@State selectedMode`
- **Header text**: `.transition(.opacity)` crossfade on mode change
- **Action bar**: slides with content (part of each mode's page)
- **DNA pattern arrows**: spring animation on helix arcs when pattern button tapped
- **Card expansion**: `.sheet` or `.fullScreenCover` with matched geometry if possible
