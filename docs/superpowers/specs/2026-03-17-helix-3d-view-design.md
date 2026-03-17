# 3D Helix View (RealityKit) — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Sub-project 2 of 3 (Engine ✅ → **3D Visualization** → Insights UI ✅)

## Context

The SleepDNA Engine produces a `SleepDNAProfile` with `helixGeometry: [DayHelixParams]` per day (twist angle, helix radius, strand thickness, surface roughness), motifs, alignments, and base pairs. This spec adds a RealityKit 3D view that renders the double helix inline in the existing DNAInsightsView.

### Design Philosophy

The 3D helix is the visual embodiment of the user's "biological DNA" — not a chart, but a living structure they can explore. It complements the narrative text sections, giving a spatial, tactile understanding of their sleep patterns.

### Constraints

- Inline in DNAInsightsView scroll (~400pt height), not a separate screen
- MiniHelixView stays as decoration above "Tu ritmo hoy"
- RealityKit (iOS 18+, already the app's minimum)
- Full interaction: rotate, zoom, tap week, toggle patterns
- Reads from existing SleepDNAProfile (no engine changes needed)

---

## 1. Scene Structure

### Entities

| Entity | Shape | Visual | Data Source |
|--------|-------|--------|-------------|
| Strand1 | Extruded tube along helix path | Purple, PBR material | helixGeometry + helix equations |
| Strand2 | Extruded tube, π phase offset | Orange, PBR material | helixGeometry + helix equations |
| Nucleotides | Spheres at each day position | Color by sleep quality (green→red gradient) | nucleotides[].features[15] |
| Base Pairs | Thin cylinders connecting strands | Gray, translucent | basePairs (PLV determines thickness) |
| Motif Regions | Semi-transparent cylinders wrapping helix | Per-motif color, shown when "Patrones" toggle ON | motifs[].instanceWeekIndices |
| Current Week | Glow outline on nucleotides | Green emissive | last 7 nucleotides |
| Similar Weeks | Glow outline on nucleotides | Cyan emissive, shown on tap | alignments[].weekIndex |

### Helix Geometry

```
// 1 full rotation = 1 week (7 days)
// Each day is a point on the helix

for day in 0..<totalDays {
    let t = Double(day) / 7.0          // turns (1 turn = 1 week)
    let params = helixGeometry[day]     // DayHelixParams
    let baseRadius = 0.3 + params.helixRadius * 0.2  // scale to scene units
    let theta = t * 2 * .pi

    // Strand 1
    let x1 = baseRadius * cos(theta)
    let y1 = baseRadius * sin(theta)
    let z1 = -Double(day) * zStep       // negative z = downward = older

    // Strand 2 (π offset + twist)
    let twist = params.twistAngle
    let x2 = baseRadius * cos(theta + .pi + twist)
    let y2 = baseRadius * sin(theta + .pi + twist)
    let z2 = z1
}
```

`zStep` scales the vertical spacing. With 52 weeks (364 days), total height ≈ 2.0 scene units.

### Materials

- **Strand tubes:** `SimpleMaterial` with metallic purple/orange, roughness from `params.surfaceRoughness`
- **Nucleotide spheres:** `SimpleMaterial`, color interpolated green→yellow→red based on sleep quality (feature[15])
- **Base pairs:** `SimpleMaterial`, gray, opacity proportional to PLV
- **Motif regions:** `SimpleMaterial`, per-motif color, opacity 0.2
- **Glow (current/similar):** `UnlitMaterial` with emissive green/cyan

---

## 2. Interactions

### Rotate

`DragGesture` on the RealityView:
- Horizontal drag → rotate scene around Y axis
- Vertical drag → rotate scene around X axis (clamped ±45°)
- Inertia: velocity-based deceleration on release
- Auto-rotation: ~2°/s around Y when no gesture active (pauses during interaction)

### Zoom

`MagnifyGesture`:
- Scale range: 0.5x — 3.0x
- At max zoom, individual nucleotide spheres are clearly visible
- Camera moves along Z axis toward center of helix

### Tap Week (hit-testing)

`SpatialTapGesture` or `TapGesture` with manual raycast:
1. Convert tap location to ray via `RealityView`
2. `scene.raycast()` to find intersected entity
3. If NucleotideEntity hit → get `day` from entity component → `weekIndex = day / 7`
4. Highlight that week green + similar weeks cyan (from `profile.alignments`)
5. Show SwiftUI overlay with similarity info
6. Dim non-related weeks (opacity 0.3)
7. Second tap on same week or tap empty space → deselect, restore all opacity

### Toggle Patterns

SwiftUI button overlaid on the RealityView (top-right corner):
- Text: "Patrones" with circle icon
- Toggle ON: show MotifRegionEntities with per-motif color + floating label
- Toggle OFF: hide MotifRegionEntities
- Only visible when `profile.tier == .full` and `!profile.motifs.isEmpty`

---

## 3. SwiftUI Integration

### DNAInsightsView Layout (updated)

```
ScrollView {
    VStack(alignment: .leading, spacing: 32) {
        MiniHelixView (decoration)
        DNAStateSection ("Tu ritmo hoy")
        HelixRealityView (profile:)          ← NEW, ~400pt
        DNAMotifSection ("Tu código genético")
        DNAAlignmentSection ("Déjà vu")
        DNAHealthSection ("Tu salud circadiana")
        DNABasePairsSection ("Qué afecta tu sueño")
        DNATierSection
    }
}
```

### HelixRealityView

```swift
struct HelixRealityView: View {
    let profile: SleepDNAProfile
    @State private var selectedWeek: Int?
    @State private var showPatterns: Bool = false
    @State private var rotationAngle: SIMD2<Float> = .zero
    @State private var zoomScale: Float = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RealityView { content in
                // Build scene from profile
            } update: { content in
                // Update highlights, patterns visibility
            }
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .gesture(tapGesture)
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Overlay controls
            if profile.tier == .full, !profile.motifs.isEmpty {
                patternsToggle
            }

            // Selected week info
            if let week = selectedWeek {
                weekInfoOverlay(week: week)
            }
        }
    }
}
```

### Overlay: Week Info

When a week is tapped, a card appears at the bottom of the 3D view:

```
┌─────────────────────────────┐
│ Semana 12 — 87% similar     │
│ Patrón: Recuperación        │
│ Calidad media: 0.72         │
└─────────────────────────────┘
```

Dismiss on tap outside or second tap on same week.

---

## 4. Performance

- **Entity count:** ~365 nucleotides + ~365 base pairs + 2 strands + ~5 motif regions ≈ 740 entities max
- **RealityKit handles this easily** on A12+ chips
- **Mesh generation:** Build helix tubes programmatically via `MeshResource.generateBox/sphere` composed along path. For tubes, use `MeshResource.generate(from:)` with custom `MeshDescriptor` (vertices along the helix path).
- **LOD:** Not needed at this scale
- **Memory:** Minimal — geometry is procedural, no textures

---

## 5. Edge Cases

- **No data (tier basic, <4 weeks):** Show the helix with available days only. Overlay: "Necesito más datos para la vista completa"
- **1 week of data:** Single turn, no motifs, no alignments. Still interactive (rotate/zoom).
- **No motifs:** "Patrones" button hidden
- **No alignments:** Tap does nothing (no similar weeks to show)
- **Profile computing:** Show MiniHelixView placeholder with ProgressView

---

## 6. File Structure

### New Files

```
spiral journey project/Views/DNA/
  HelixRealityView.swift          — SwiftUI wrapper with RealityView, gestures, overlays
  HelixSceneBuilder.swift         — builds RealityKit entities from SleepDNAProfile
  HelixInteractionManager.swift   — handles rotation, zoom, tap, auto-rotation, selection state
```

### Modified Files

```
spiral journey project/Views/DNA/DNAInsightsView.swift — insert HelixRealityView after DNAStateSection
```

---

## 7. Testing Strategy

- **HelixSceneBuilder:** Unit tests for helix coordinate computation (known day → expected position)
- **Interaction:** Manual testing in simulator — rotate, zoom, tap
- **Edge cases:** Preview with mock profiles (empty, basic, intermediate, full)
- **Performance:** Profile entity count and frame rate with 365 days of data

---

## 8. Implementation Order

```
1. HelixSceneBuilder           — generate geometry from profile
2. HelixRealityView            — RealityView wrapper + basic rendering
3. HelixInteractionManager     — rotate, zoom, auto-rotation
4. Tap + week selection        — hit-testing, highlights, overlay
5. Patterns toggle             — motif regions, labels
6. DNAInsightsView integration — insert inline
7. Edge cases + polish         — empty states, loading, performance
```
