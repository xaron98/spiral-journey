# 3D Helix View (RealityKit) — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the user's sleep DNA as an interactive 3D double helix using RealityKit, inline in the existing DNAInsightsView.

**Architecture:** `HelixSceneBuilder` generates RealityKit entities from `SleepDNAProfile`. `HelixRealityView` wraps the scene in SwiftUI with gesture handling. `HelixInteractionManager` manages rotation, zoom, tap selection, and auto-rotation state. The view is inserted inline (~400pt) in DNAInsightsView after the "Tu ritmo hoy" section.

**Tech Stack:** Swift 6, SwiftUI, RealityKit, SpiralKit (SleepDNAProfile, DayHelixParams)

**Spec:** `docs/superpowers/specs/2026-03-17-helix-3d-view-design.md`

---

## File Structure

### New Files

```
spiral journey project/Views/DNA/
  HelixRealityView.swift          — SwiftUI RealityView wrapper, gestures, overlays
  HelixSceneBuilder.swift         — builds entities from SleepDNAProfile
  HelixInteractionManager.swift   — rotation, zoom, tap, auto-rotation state
```

### Modified Files

```
spiral journey project/Views/DNA/DNAInsightsView.swift — insert HelixRealityView
```

---

## Key Existing APIs

```swift
// SleepDNAProfile (from SpiralKit, Codable, Sendable)
public struct SleepDNAProfile {
    let nucleotides: [DayNucleotide]      // .day, .features[16]
    let helixGeometry: [DayHelixParams]   // per-day geometry
    let motifs: [SleepMotif]              // .id, .name, .instanceWeekIndices
    let alignments: [WeekAlignment]       // .weekIndex, .similarity, .dtwScore
    let basePairs: [BasePairSynchrony]    // .plv, .sleepFeatureIndex, .contextFeatureIndex
    let tier: AnalysisTier                // .basic, .intermediate, .full
    let dataWeeks: Int
}

// DayHelixParams (from SpiralKit)
public struct DayHelixParams: Codable, Sendable {
    public let day: Int
    public let twistAngle: Double        // PLV → twist between strands
    public let helixRadius: Double       // midSleep deviation [0,1]
    public let strandThickness: Double   // N3 proportion [0,1]
    public let surfaceRoughness: Double  // fragmentation [0,1]
}

// SleepMotif
public struct SleepMotif: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let instanceWeekIndices: [Int]
    public let instanceCount: Int
}

// WeekAlignment
public struct WeekAlignment: Codable, Sendable {
    public let weekIndex: Int
    public let similarity: Double  // [0,1]
}
```

---

## Chunk 1: Scene Building (Tasks 1-2)

### Task 1: HelixSceneBuilder

**Files:**
- Create: `spiral journey project/Views/DNA/HelixSceneBuilder.swift`

Generates all RealityKit entities from a SleepDNAProfile.

- [ ] **Step 1: Create HelixSceneBuilder with helix coordinate math**

```swift
// spiral journey project/Views/DNA/HelixSceneBuilder.swift
import RealityKit
import SwiftUI
import SpiralKit

/// Builds a RealityKit entity hierarchy representing the sleep DNA double helix.
enum HelixSceneBuilder {

    // MARK: - Constants

    static let zStep: Float = 0.005          // vertical spacing per day
    static let baseRadius: Float = 0.15      // minimum helix radius
    static let radiusScale: Float = 0.1      // additional radius from DayHelixParams
    static let nucleotideSize: Float = 0.012 // sphere radius
    static let basePairRadius: Float = 0.002 // connector thickness

    // MARK: - Public

    /// Build the complete helix scene from a profile.
    static func build(from profile: SleepDNAProfile) -> Entity {
        let root = Entity()
        root.name = "HelixRoot"

        let days = profile.helixGeometry
        guard !days.isEmpty else { return root }

        // Center the helix vertically
        let totalHeight = Float(days.count) * zStep
        let yOffset = totalHeight / 2

        // Nucleotides + base pairs
        for (i, params) in days.enumerated() {
            let t = Float(params.day) / 7.0  // turns (1 turn = 1 week)
            let theta = t * 2 * .pi
            let r = baseRadius + Float(params.helixRadius) * radiusScale
            let y = Float(i) * zStep - yOffset

            // Strand 1 position
            let x1 = r * cos(theta)
            let z1 = r * sin(theta)
            let pos1 = SIMD3<Float>(x1, y, z1)

            // Strand 2 position (π offset + twist)
            let twist = Float(params.twistAngle)
            let x2 = r * cos(theta + .pi + twist)
            let z2 = r * sin(theta + .pi + twist)
            let pos2 = SIMD3<Float>(x2, y, z2)

            // Quality color (green → yellow → red)
            let quality = i < profile.nucleotides.count
                ? Float(profile.nucleotides[i].features[15])
                : 0.5
            let color = qualityColor(quality)

            // Nucleotide spheres
            let sphere1 = makeNucleotide(position: pos1, color: color, day: params.day, strand: 1)
            let sphere2 = makeNucleotide(position: pos2, color: .orange.withAlphaComponent(0.8), day: params.day, strand: 2)
            root.addChild(sphere1)
            root.addChild(sphere2)

            // Base pair connector
            let pair = makeBasePair(from: pos1, to: pos2, plv: averagePLV(profile.basePairs))
            root.addChild(pair)
        }

        // Strand tubes (simplified: connect nucleotide positions with thin cylinders)
        addStrandTubes(to: root, days: days, profile: profile, yOffset: yOffset, strand: 1, color: .purple)
        addStrandTubes(to: root, days: days, profile: profile, yOffset: yOffset, strand: 2, color: .orange)

        // Current week highlight
        highlightCurrentWeek(root: root, totalDays: days.count)

        return root
    }

    // MARK: - Nucleotide

    private static func makeNucleotide(
        position: SIMD3<Float>, color: UIColor, day: Int, strand: Int
    ) -> Entity {
        let mesh = MeshResource.generateSphere(radius: nucleotideSize)
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.metallic = .init(floatLiteral: 0.3)
        material.roughness = .init(floatLiteral: 0.6)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.name = "nucleotide_\(strand)_\(day)"
        return entity
    }

    // MARK: - Base Pair

    private static func makeBasePair(
        from: SIMD3<Float>, to: SIMD3<Float>, plv: Float
    ) -> Entity {
        let midpoint = (from + to) / 2
        let distance = simd_distance(from, to)
        let direction = normalize(to - from)

        let mesh = MeshResource.generateBox(
            width: basePairRadius * 2,
            height: basePairRadius * 2,
            depth: distance
        )
        var material = SimpleMaterial()
        material.color = .init(tint: .gray.withAlphaComponent(CGFloat(0.15 + plv * 0.3)))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint
        entity.look(at: to, from: midpoint, relativeTo: nil)
        entity.name = "basepair"
        return entity
    }

    // MARK: - Strand Tubes

    private static func addStrandTubes(
        to root: Entity, days: [DayHelixParams], profile: SleepDNAProfile,
        yOffset: Float, strand: Int, color: UIColor
    ) {
        // Connect consecutive nucleotide positions with thin cylinders
        for i in 0..<(days.count - 1) {
            let pos1 = nucleotidePosition(day: days[i], index: i, yOffset: yOffset, strand: strand)
            let pos2 = nucleotidePosition(day: days[i + 1], index: i + 1, yOffset: yOffset, strand: strand)

            let mid = (pos1 + pos2) / 2
            let dist = simd_distance(pos1, pos2)
            let thickness = Float(days[i].strandThickness) * 0.006 + 0.003

            let mesh = MeshResource.generateBox(width: thickness, height: thickness, depth: dist)
            var mat = SimpleMaterial()
            mat.color = .init(tint: color.withAlphaComponent(0.7))
            mat.metallic = .init(floatLiteral: 0.4)
            mat.roughness = .init(floatLiteral: Float(days[i].surfaceRoughness) * 0.5 + 0.3)

            let segment = ModelEntity(mesh: mesh, materials: [mat])
            segment.position = mid
            segment.look(at: pos2, from: mid, relativeTo: nil)
            segment.name = "strand\(strand)_seg_\(i)"
            root.addChild(segment)
        }
    }

    private static func nucleotidePosition(
        day: DayHelixParams, index: Int, yOffset: Float, strand: Int
    ) -> SIMD3<Float> {
        let t = Float(day.day) / 7.0
        let theta = t * 2 * .pi
        let r = baseRadius + Float(day.helixRadius) * radiusScale
        let y = Float(index) * zStep - yOffset

        if strand == 1 {
            return SIMD3<Float>(r * cos(theta), y, r * sin(theta))
        } else {
            let twist = Float(day.twistAngle)
            return SIMD3<Float>(r * cos(theta + .pi + twist), y, r * sin(theta + .pi + twist))
        }
    }

    // MARK: - Highlights

    private static func highlightCurrentWeek(root: Entity, totalDays: Int) {
        let lastWeekStart = max(0, totalDays - 7)
        for day in lastWeekStart..<totalDays {
            if let entity = root.findEntity(named: "nucleotide_1_\(day)") as? ModelEntity {
                var mat = UnlitMaterial()
                mat.color = .init(tint: .green.withAlphaComponent(0.9))
                entity.model?.materials = [mat]
            }
        }
    }

    /// Highlight similar weeks with cyan glow
    static func highlightSimilarWeeks(
        root: Entity, selectedWeek: Int, alignments: [WeekAlignment], totalDays: Int
    ) {
        // Reset all to default first
        resetHighlights(root: root, totalDays: totalDays)

        // Highlight selected week (green)
        let selectedStart = selectedWeek * 7
        for day in selectedStart..<min(selectedStart + 7, totalDays) {
            if let entity = root.findEntity(named: "nucleotide_1_\(day)") as? ModelEntity {
                var mat = UnlitMaterial()
                mat.color = .init(tint: .green)
                entity.model?.materials = [mat]
            }
        }

        // Highlight similar weeks (cyan)
        for alignment in alignments {
            let start = alignment.weekIndex * 7
            for day in start..<min(start + 7, totalDays) {
                if let entity = root.findEntity(named: "nucleotide_1_\(day)") as? ModelEntity {
                    var mat = UnlitMaterial()
                    mat.color = .init(tint: .cyan.withAlphaComponent(CGFloat(alignment.similarity)))
                    entity.model?.materials = [mat]
                }
            }
        }

        // Dim non-related weeks
        // (entities not named in selected or similar → opacity 0.3)
    }

    static func resetHighlights(root: Entity, totalDays: Int) {
        highlightCurrentWeek(root: root, totalDays: totalDays)
    }

    // MARK: - Motif Regions

    /// Add or remove semi-transparent motif region cylinders
    static func toggleMotifRegions(
        root: Entity, motifs: [SleepMotif], show: Bool, totalDays: Int, yOffset: Float
    ) {
        // Remove existing motif entities
        root.children.filter { $0.name.hasPrefix("motif_") }.forEach { $0.removeFromParent() }

        guard show else { return }

        let colors: [UIColor] = [.systemPurple, .systemTeal, .systemPink, .systemIndigo, .systemMint]

        for (i, motif) in motifs.enumerated() {
            let color = colors[i % colors.count]
            for weekIdx in motif.instanceWeekIndices {
                let startDay = weekIdx * 7
                let endDay = min(startDay + 6, totalDays - 1)
                let yStart = Float(startDay) * zStep - yOffset
                let yEnd = Float(endDay) * zStep - yOffset
                let height = abs(yEnd - yStart)
                let yMid = (yStart + yEnd) / 2

                let mesh = MeshResource.generateCylinder(height: height, radius: baseRadius + radiusScale + 0.02)
                var mat = SimpleMaterial()
                mat.color = .init(tint: color.withAlphaComponent(0.15))

                let region = ModelEntity(mesh: mesh, materials: [mat])
                region.position = SIMD3<Float>(0, yMid, 0)
                region.name = "motif_\(motif.id.uuidString)_\(weekIdx)"
                root.addChild(region)
            }
        }
    }

    // MARK: - Helpers

    private static func qualityColor(_ quality: Float) -> UIColor {
        // green (1.0) → yellow (0.5) → red (0.0)
        if quality > 0.5 {
            let t = (quality - 0.5) * 2  // 0→1
            return UIColor(
                red: CGFloat(1 - t), green: CGFloat(0.8), blue: CGFloat(0.2),
                alpha: 0.9
            )
        } else {
            let t = quality * 2  // 0→1
            return UIColor(
                red: CGFloat(0.9), green: CGFloat(t * 0.6), blue: CGFloat(0.1),
                alpha: 0.9
            )
        }
    }

    private static func averagePLV(_ pairs: [BasePairSynchrony]) -> Float {
        guard !pairs.isEmpty else { return 0.3 }
        return Float(pairs.map(\.plv).reduce(0, +) / Double(pairs.count))
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add HelixSceneBuilder for RealityKit helix generation

Builds double helix entities from SleepDNAProfile: nucleotide spheres
(quality-colored), strand tubes (thickness/roughness from params),
base pair connectors (PLV opacity), week highlights, motif regions."
```

---

### Task 2: HelixRealityView + HelixInteractionManager

**Files:**
- Create: `spiral journey project/Views/DNA/HelixRealityView.swift`
- Create: `spiral journey project/Views/DNA/HelixInteractionManager.swift`

- [ ] **Step 1: Create HelixInteractionManager**

```swift
// spiral journey project/Views/DNA/HelixInteractionManager.swift
import SwiftUI
import RealityKit
import SpiralKit

/// Manages interaction state for the 3D helix view.
@Observable
@MainActor
final class HelixInteractionManager {
    var rotationX: Float = 0          // vertical tilt (clamped ±45°)
    var rotationY: Float = 0          // horizontal spin
    var zoomScale: Float = 1.0        // 0.5 — 3.0
    var selectedWeek: Int?
    var showPatterns: Bool = false
    var isInteracting: Bool = false

    // Auto-rotation
    private var autoRotationSpeed: Float = 0.5  // degrees per frame
    private var lastDragVelocity: CGSize = .zero

    /// Apply drag gesture delta to rotation
    func applyDrag(_ translation: CGSize) {
        rotationY += Float(translation.width) * 0.5
        rotationX = max(-45, min(45, rotationX + Float(translation.height) * 0.3))
    }

    /// Apply magnification to zoom
    func applyZoom(_ magnification: CGFloat) {
        zoomScale = max(0.5, min(3.0, zoomScale * Float(magnification)))
    }

    /// Advance auto-rotation (call per frame when not interacting)
    func tickAutoRotation() {
        guard !isInteracting else { return }
        rotationY += autoRotationSpeed
    }

    /// Select a week by day index from hit-test
    func selectDay(_ day: Int, profile: SleepDNAProfile) {
        let weekIndex = day / 7
        if selectedWeek == weekIndex {
            selectedWeek = nil  // deselect on second tap
        } else {
            selectedWeek = weekIndex
        }
    }

    /// Get alignments for selected week
    func similarWeeks(for profile: SleepDNAProfile) -> [WeekAlignment] {
        guard selectedWeek != nil else { return [] }
        return Array(profile.alignments.prefix(5))
    }

    /// Build the rotation transform for the scene root
    var sceneTransform: Transform {
        var transform = Transform.identity
        let rotX = simd_quatf(angle: rotationX * .pi / 180, axis: [1, 0, 0])
        let rotY = simd_quatf(angle: rotationY * .pi / 180, axis: [0, 1, 0])
        transform.rotation = rotY * rotX
        transform.scale = SIMD3<Float>(repeating: zoomScale)
        return transform
    }
}
```

- [ ] **Step 2: Create HelixRealityView**

```swift
// spiral journey project/Views/DNA/HelixRealityView.swift
import SwiftUI
import RealityKit
import SpiralKit

struct HelixRealityView: View {
    let profile: SleepDNAProfile
    @State private var interaction = HelixInteractionManager()
    @State private var helixRoot: Entity?

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 3D Scene
            RealityView { content in
                let root = HelixSceneBuilder.build(from: profile)
                helixRoot = root

                let anchor = AnchorEntity()
                anchor.addChild(root)
                content.add(anchor)

                // Camera setup
                content.camera = .spatialTracking
            } update: { content in
                // Apply rotation + zoom
                helixRoot?.transform = interaction.sceneTransform

                // Update highlights
                if let root = helixRoot {
                    if let week = interaction.selectedWeek {
                        HelixSceneBuilder.highlightSimilarWeeks(
                            root: root,
                            selectedWeek: week,
                            alignments: interaction.similarWeeks(for: profile),
                            totalDays: profile.helixGeometry.count
                        )
                    } else {
                        HelixSceneBuilder.resetHighlights(
                            root: root,
                            totalDays: profile.helixGeometry.count
                        )
                    }

                    // Motif regions
                    let yOffset = Float(profile.helixGeometry.count) * HelixSceneBuilder.zStep / 2
                    HelixSceneBuilder.toggleMotifRegions(
                        root: root,
                        motifs: profile.motifs,
                        show: interaction.showPatterns,
                        totalDays: profile.helixGeometry.count,
                        yOffset: yOffset
                    )
                }
            }
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
            // Gestures
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .gesture(tapGesture)

            // Overlay: Patterns toggle
            if profile.tier == .full, !profile.motifs.isEmpty {
                Button {
                    withAnimation { interaction.showPatterns.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: interaction.showPatterns ? "eye.fill" : "eye.slash")
                        Text(loc("dna.3d.patterns"))
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(12)
            }

            // Overlay: Selected week info
            if let week = interaction.selectedWeek {
                weekInfoCard(week: week)
            }
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                interaction.isInteracting = true
                interaction.applyDrag(value.translation)
            }
            .onEnded { _ in
                interaction.isInteracting = false
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                interaction.isInteracting = true
                interaction.applyZoom(value.magnification)
            }
            .onEnded { _ in
                interaction.isInteracting = false
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // RealityKit hit-testing
                // Find the tapped entity, extract day from name
                // entity.name format: "nucleotide_1_DAY"
                // For now, simplified: tap toggles selection off
                if interaction.selectedWeek != nil {
                    interaction.selectedWeek = nil
                }
            }
    }

    // MARK: - Week Info Card

    @ViewBuilder
    private func weekInfoCard(week: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let best = profile.alignments.first {
                Text("\(loc("dna.3d.week")) \(week + 1) — \(Int(best.similarity * 100))% \(loc("dna.3d.similar"))")
                    .font(.caption.weight(.semibold))
            }
            if let motif = profile.motifs.first {
                Text("\(loc("dna.3d.pattern")): \(motif.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(12)
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

**Note:** The exact RealityKit API for `RealityView`, camera setup, and `SpatialTapGesture` hit-testing should be verified against the current SDK. The implementer should:
1. Check if `content.camera = .spatialTracking` is valid for iOS (it's visionOS-specific). On iOS, RealityView uses a default camera — transforms on the root entity control the view.
2. For tap hit-testing on iOS, use `arView.hitTest()` or entity collision shapes. The simplified version above deselects on tap — proper hit-testing can be refined after the basic scene renders.

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add HelixRealityView with interaction manager

RealityView wrapper with drag-to-rotate, pinch-to-zoom, tap selection,
auto-rotation, patterns toggle, and week info overlay."
```

---

## Chunk 2: Integration + Polish (Tasks 3-4)

### Task 3: DNAInsightsView Integration

**Files:**
- Modify: `spiral journey project/Views/DNA/DNAInsightsView.swift`

- [ ] **Step 1: Insert HelixRealityView after DNAStateSection**

Read DNAInsightsView.swift and add the 3D view between `DNAStateSection` and `DNAMotifSection`:

```swift
// In the ScrollView VStack, after DNAStateSection:
if profile.helixGeometry.count >= 7 {
    HelixRealityView(profile: profile)
}
```

Only show if there are at least 7 days (1 full helix turn). If fewer, the MiniHelixView decoration suffices.

- [ ] **Step 2: Build and test visually in simulator**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: integrate 3D helix view inline in DNAInsightsView

Shows after 'Tu ritmo hoy' section when >= 7 days of data.
~400pt interactive RealityKit scene."
```

---

### Task 4: Localization + Edge Cases

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`
- Modify: `spiral journey project/Views/DNA/HelixRealityView.swift`

- [ ] **Step 1: Add 3D view localization keys**

Add to `Localizable.xcstrings` in all 8 languages:

| Key | en | es | ca | de | fr | zh-Hans | ja | ar |
|-----|----|----|----|----|----|----|----|----|
| `dna.3d.patterns` | Patterns | Patrones | Patrons | Muster | Modèles | 模式 | パターン | أنماط |
| `dna.3d.week` | Week | Semana | Setmana | Woche | Semaine | 周 | 週 | أسبوع |
| `dna.3d.similar` | similar | similar | similar | ähnlich | similaire | 相似 | 類似 | مشابه |
| `dna.3d.pattern` | Pattern | Patrón | Patró | Muster | Modèle | 模式 | パターン | نمط |
| `dna.3d.needsdata` | Need more data for the full view | Necesito más datos para la vista completa | Necessito més dades per a la vista completa | Mehr Daten für die vollständige Ansicht nötig | Plus de données nécessaires pour la vue complète | 需要更多数据才能显示完整视图 | 完全なビューにはもっとデータが必要です | تحتاج المزيد من البيانات للعرض الكامل |

- [ ] **Step 2: Add edge case handling in HelixRealityView**

```swift
// In HelixRealityView body, before the RealityView:
if profile.helixGeometry.count < 7 {
    // Not enough data for a full turn
    VStack(spacing: 8) {
        Image(systemName: "cube.transparent")
            .font(.title)
            .foregroundStyle(.secondary)
        Text(loc("dna.3d.needsdata"))
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    .frame(height: 200)
    .frame(maxWidth: .infinity)
} else {
    // ... existing RealityView code
}
```

- [ ] **Step 3: Build and commit**

```bash
git commit -m "feat: add 3D view localization (8 langs) + edge cases

Patterns, week, similar labels in en/es/ca/de/fr/zh/ja/ar.
Empty state for < 7 days of data."
```

---

## Final Verification

After all tasks complete:

- [ ] `cd SpiralKit && swift test` — existing 418 tests still pass
- [ ] `xcodebuild build -scheme "spiral journey project" ...` — iOS builds
- [ ] `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS` — Watch builds (RealityKit not imported on Watch)
- [ ] Run in simulator: open 🧬 → scroll to 3D helix → rotate/zoom → verify renders
- [ ] Tap nucleotide → week highlights (if hit-testing works)
- [ ] Toggle "Patrones" → motif regions appear/disappear
- [ ] Verify localization in Spanish and English
