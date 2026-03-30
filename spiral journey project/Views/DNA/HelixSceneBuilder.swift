import RealityKit
import SwiftUI
import SpiralKit

/// Builds a RealityKit double-helix modeled after classic molecular DNA:
/// two thick smooth cylindrical backbone tubes spiraling around each other
/// with chunky colored bar connectors between them.
@available(iOS 18.0, *)
enum HelixSceneBuilder {

    // MARK: - Geometry Constants

    private static let helixRadius: Float = 0.18
    /// Backbone tube radius — prominent structural guide.
    private static let backboneRadius: Float = 0.015
    /// Joint sphere radius — matches tube for seamless look.
    private static let jointRadius: Float = 0.015
    /// Connector bar radius — thinner than backbone, shows sleep data pattern.
    private static let barRadius: Float = 0.011
    /// Vertical rise per full turn.
    private static let pitchPerTurn: Float = 0.28
    /// Segments per full turn — very high for seamless smooth tube.
    private static let segmentsPerTurn: Int = 72
    /// Connector bars per full turn.
    private static let barsPerTurn: Int = 10

    // MARK: - Materials (cached)

    /// Strand 1 (current/today) = warm gold
    private static let backbone1Color: UIColor = UIColor(red: 0.92, green: 0.68, blue: 0.20, alpha: 1.0)
    /// Strand 2 (previous/yesterday) = cool silver
    private static let backbone2Color: UIColor = UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1.0)
    private static let deepColor: UIColor = UIColor(red: 0.10, green: 0.16, blue: 0.43, alpha: 1.0)
    private static let remColor: UIColor = UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1.0)
    private static let lightColor: UIColor = UIColor(red: 0.29, green: 0.48, blue: 0.71, alpha: 1.0)
    private static let awakeColor: UIColor = UIColor(red: 0.83, green: 0.66, blue: 0.38, alpha: 1.0)
    private static let highlightColor: UIColor = UIColor(Color(hex: "22d3ee"))

    /// Glossy metallic backbone material.
    private static func backboneMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.roughness = .init(floatLiteral: 0.15)
        mat.metallic = .init(floatLiteral: 0.6)
        mat.clearcoat = .init(floatLiteral: 0.8)
        mat.clearcoatRoughness = .init(floatLiteral: 0.05)
        return mat
    }

    /// Vivid glossy material for connector bars — the visual protagonist.
    private static func barMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.roughness = .init(floatLiteral: 0.15)
        mat.metallic = .init(floatLiteral: 0.4)
        mat.clearcoat = .init(floatLiteral: 0.7)
        mat.clearcoatRoughness = .init(floatLiteral: 0.05)
        mat.emissiveColor = .init(color: color.withAlphaComponent(0.15))
        mat.emissiveIntensity = 0.3
        return mat
    }

    // MARK: - Build

    static func build(
        from profile: SleepDNAProfile,
        strand1Records: [SleepRecord] = [],
        strand2Records: [SleepRecord] = []
    ) -> Entity {
        let root = Entity()
        root.name = "helix_root"

        let totalDays = profile.nucleotides.count
        guard totalDays >= 3 else { return root }

        let totalTurns = Float(totalDays) / 7.0
        let totalHeight = totalTurns * pitchPerTurn
        let yOffset = totalHeight / 2.0
        let totalSegments = Int(totalTurns * Float(segmentsPerTurn))
        let bb1Mat = backboneMaterial(color: backbone1Color) // gold = current
        let bb2Mat = backboneMaterial(color: backbone2Color) // silver = previous

        // --- Two smooth backbone tubes (180° apart) ---
        buildSmoothTube(root: root, totalSegments: totalSegments, yOffset: yOffset, phaseOffset: 0, material: bb1Mat, tag: "backbone1")
        buildSmoothTube(root: root, totalSegments: totalSegments, yOffset: yOffset, phaseOffset: .pi, material: bb2Mat, tag: "backbone2")

        // --- Connector bars ---
        // Build positional arrays: index 0 = first day in helix, etc.
        // For modes like "best" where strand2 has 1 record, we replicate it.
        var s1ByDay: [Int: SleepRecord] = [:]
        for (i, rec) in strand1Records.enumerated() {
            s1ByDay[rec.day] = rec
            // Also map by position for small arrays
            if strand1Records.count <= 2 { s1ByDay[i] = rec }
        }
        var s2ByDay: [Int: SleepRecord] = [:]
        for (i, rec) in strand2Records.enumerated() {
            s2ByDay[rec.day] = rec
            if strand2Records.count <= 2 { s2ByDay[i] = rec }
        }
        // Single-record strands: replicate across all days
        let s1Single = strand1Records.count == 1 ? strand1Records.first : nil
        let s2Single = strand2Records.count == 1 ? strand2Records.first : nil

        let totalBars = Int(totalTurns * Float(barsPerTurn))
        for i in 0..<totalBars {
            let t = Float(i) / Float(barsPerTurn)
            let theta = t * 2 * .pi
            let y = t * pitchPerTurn - yOffset

            let pos1 = SIMD3<Float>(helixRadius * cos(theta), y, helixRadius * sin(theta))
            let pos2 = SIMD3<Float>(helixRadius * cos(theta + .pi), y, helixRadius * sin(theta + .pi))
            let center = (pos1 + pos2) / 2

            let dayIndex = min(Int(t * 7), totalDays - 1)
            let record1 = s1Single ?? s1ByDay[dayIndex]
            let record2 = s2Single ?? s2ByDay[dayIndex]
            let slotInDay = i % barsPerTurn

            let (color1, color2) = barColors(
                record: record1,
                previousRecord: record2,
                slotIndex: slotInDay,
                totalSlots: barsPerTurn
            )

            // Parent entity for the whole bar — carries collision for tap detection
            let barParent = Entity()
            barParent.name = "bar_\(i)"
            barParent.position = center

            // Collision box: wide along bar direction, thick enough to tap easily,
            // but height limited to vertical spacing to reduce overlap with neighbors
            let barLength = simd_length(pos2 - pos1)
            let verticalSpacing = pitchPerTurn / Float(barsPerTurn) // ~0.028
            let hitThick: Float = barRadius * 3  // 3× visual radius for easy tap
            let hitHeight: Float = min(verticalSpacing * 0.9, hitThick) // don't exceed neighbor spacing
            barParent.components.set(CollisionComponent(
                shapes: [.generateBox(width: hitThick, height: barLength * 1.1, depth: hitThick)]
            ))
            barParent.components.set(InputTargetComponent())

            // Orient collision box along the bar direction
            let barDir = simd_normalize(pos2 - pos1)
            let up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(up, barDir)) < 0.999 {
                barParent.transform.rotation = simd_quatf(from: up, to: barDir)
            }

            // Visual half-bars as children of the parent
            let half1 = makeCylinder(from: pos1, to: center, radius: barRadius, material: barMaterial(color: color1))
            half1.name = "bar_\(i)_h1"
            root.addChild(half1)

            let half2 = makeCylinder(from: center, to: pos2, radius: barRadius, material: barMaterial(color: color2))
            half2.name = "bar_\(i)_h2"
            root.addChild(half2)

            root.addChild(barParent)

            // Small sphere at junction where bar meets backbone
            let cap1 = makeSphere(at: pos1, radius: barRadius * 1.1, material: barMaterial(color: color1))
            cap1.name = "bar_\(i)_c1"
            root.addChild(cap1)
            let cap2 = makeSphere(at: pos2, radius: barRadius * 1.1, material: barMaterial(color: color2))
            cap2.name = "bar_\(i)_c2"
            root.addChild(cap2)

            // Invisible anchor for highlight/nucleotide compatibility
            if slotInDay == 0 {
                let anchor1 = Entity()
                anchor1.name = "nucleotide_1_\(dayIndex)"
                anchor1.position = pos1
                root.addChild(anchor1)
                let anchor2 = Entity()
                anchor2.name = "nucleotide_2_\(dayIndex)"
                anchor2.position = pos2
                root.addChild(anchor2)
            }
        }

        return root
    }

    // MARK: - Smooth Tube

    /// Build a smooth cylindrical tube along a helix path.
    /// Uses cylinder segments between points + spheres at every joint to hide seams.
    private static func buildSmoothTube(
        root: Entity,
        totalSegments: Int,
        yOffset: Float,
        phaseOffset: Float,
        material: PhysicallyBasedMaterial,
        tag: String
    ) {
        var prevPoint: SIMD3<Float>?

        for i in 0...totalSegments {
            let t = Float(i) / Float(segmentsPerTurn)
            let theta = t * 2 * .pi + phaseOffset
            let y = t * pitchPerTurn - yOffset
            let point = SIMD3<Float>(helixRadius * cos(theta), y, helixRadius * sin(theta))

            // Joint sphere at every point — hides cylinder seams
            let joint = makeSphere(at: point, radius: jointRadius, material: material)
            joint.name = "\(tag)_joint_\(i)"
            root.addChild(joint)

            // Cylinder segment connecting to previous point
            if let prev = prevPoint {
                let seg = makeCylinder(from: prev, to: point, radius: backboneRadius, material: material)
                seg.name = "\(tag)_seg_\(i)"
                root.addChild(seg)
            }

            prevPoint = point
        }
    }

    // MARK: - Primitives

    private static func makeCylinder(
        from a: SIMD3<Float>,
        to b: SIMD3<Float>,
        radius: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity {
        let diff = b - a
        let length = simd_length(diff)
        guard length > 0.0005 else { return ModelEntity() }

        let mesh = MeshResource.generateCylinder(height: length, radius: radius)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = (a + b) / 2

        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(diff)
        if abs(simd_dot(up, dir)) < 0.999 {
            entity.transform.rotation = simd_quatf(from: up, to: dir)
        }
        return entity
    }

    private static func makeSphere(
        at position: SIMD3<Float>,
        radius: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: radius)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        return entity
    }

    // MARK: - Bar Colors

    private static func barColors(
        record: SleepRecord?,
        previousRecord: SleepRecord?,
        slotIndex: Int,
        totalSlots: Int
    ) -> (UIColor, UIColor) {
        (phaseColorForSlot(record: record, slotIndex: slotIndex, totalSlots: totalSlots),
         phaseColorForSlot(record: previousRecord, slotIndex: slotIndex, totalSlots: totalSlots))
    }

    private static func phaseColorForSlot(record: SleepRecord?, slotIndex: Int, totalSlots: Int) -> UIColor {
        guard let record = record, !record.phases.isEmpty else {
            return lightColor.withAlphaComponent(0.4)
        }
        let phaseIdx = min(Int(Float(slotIndex) / Float(totalSlots) * Float(record.phases.count)), record.phases.count - 1)
        return phaseColor(record.phases[phaseIdx].phase)
    }

    /// Compute the 3D center position of each bar for hit-testing.
    /// Returns array indexed by global bar index.
    static func barCenterPositions(totalDays: Int) -> [SIMD3<Float>] {
        let totalTurns = Float(totalDays) / 7.0
        let totalHeight = totalTurns * pitchPerTurn
        let yOff = totalHeight / 2.0
        let totalBars = Int(totalTurns * Float(barsPerTurn))

        var positions: [SIMD3<Float>] = []
        for i in 0..<totalBars {
            let t = Float(i) / Float(barsPerTurn)
            let theta = t * 2 * .pi
            let y = t * pitchPerTurn - yOff
            let pos1 = SIMD3<Float>(helixRadius * cos(theta), y, helixRadius * sin(theta))
            let pos2 = SIMD3<Float>(helixRadius * cos(theta + .pi), y, helixRadius * sin(theta + .pi))
            positions.append((pos1 + pos2) / 2)
        }
        return positions
    }

    private static func phaseColor(_ phase: SleepPhase) -> UIColor {
        switch phase {
        case .deep:  return deepColor
        case .light: return lightColor
        case .rem:   return remColor
        case .awake: return awakeColor
        }
    }

    // MARK: - Slot Highlight

    /// Highlight a selected bar (glow + scale up) and dim all others.
    /// Pass nil to reset everything.
    /// Bar entities are named "bar_{globalIndex}_h1", "bar_{globalIndex}_h2",
    /// "bar_{globalIndex}_c1", "bar_{globalIndex}_c2".
    static func highlightSlot(root: Entity, selectedSlot: Int?) {
        for child in root.children {
            guard child.name.hasPrefix("bar_"), let model = child as? ModelEntity else { continue }

            // Extract global index from name: "bar_42_h1" → 42
            let parts = child.name.components(separatedBy: "_")
            guard parts.count >= 3, let barIndex = Int(parts[1]) else { continue }

            if let slot = selectedSlot {
                let isSelected = barIndex == slot

                if isSelected {
                    model.scale = SIMD3<Float>(1.8, 1.0, 1.8)
                    if var mat = model.model?.materials.first as? PhysicallyBasedMaterial {
                        mat.emissiveIntensity = 1.5
                        model.model?.materials = [mat]
                    }
                } else {
                    model.scale = .one
                    if var mat = model.model?.materials.first as? PhysicallyBasedMaterial {
                        mat.blending = .transparent(opacity: .init(floatLiteral: 0.35))
                        mat.emissiveIntensity = 0
                        model.model?.materials = [mat]
                    }
                }
            } else {
                model.scale = .one
                if var mat = model.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.blending = .opaque
                    mat.emissiveIntensity = 0.3
                    model.model?.materials = [mat]
                }
            }
        }
    }

    // MARK: - Highlight / Reset / Motif / LOD (API compatibility)

    static func highlightSimilarWeeks(root: Entity, selectedWeek: Int, alignments: [WeekAlignment], totalDays: Int) {
        let threshold: Double = 0.5
        let similarWeeks = Set(
            alignments.filter { $0.similarity >= threshold && $0.weekIndex != selectedWeek }.map(\.weekIndex)
            + [selectedWeek]
        )
        let barsPerTurn = 10
        for child in root.children where child.name.hasPrefix("bar_") {
            guard let model = child as? ModelEntity else { continue }
            let parts = child.name.components(separatedBy: "_")
            guard parts.count >= 3, let barIndex = Int(parts[1]) else { continue }
            let day = barIndex * 7 / max(1, barsPerTurn)
            let week = day / 7
            guard similarWeeks.contains(week) else { continue }
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: highlightColor)
            mat.emissiveColor = .init(color: highlightColor.withAlphaComponent(0.4))
            mat.emissiveIntensity = 1.5
            mat.roughness = .init(floatLiteral: 0.2)
            model.model?.materials = [mat]
        }
    }

    static func resetHighlights(root: Entity, totalDays: Int) {
        // Bars keep their phase colors from build — just remove emissive
        for child in root.children where child.name.hasPrefix("bar_") {
            guard let model = child as? ModelEntity else { continue }
            // Reset to default bar appearance
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: lightColor)
            mat.roughness = .init(floatLiteral: 0.25)
            mat.metallic = .init(floatLiteral: 0.3)
            model.model?.materials = [mat]
        }
    }

    static let motifColorPalette: [UIColor] = [
        UIColor(Color(hex: "22d3ee")),
        UIColor(Color(hex: "a78bfa")),
        UIColor(Color(hex: "34d399")),
        UIColor(Color(hex: "fb923c")),
    ]

    static func toggleMotifRegions(root: Entity, motifs: [SleepMotif], show: Bool, totalDays: Int, yOffset: Float? = nil) {
        var dayMotifColor: [Int: UIColor] = [:]
        if show {
            for (idx, motif) in motifs.enumerated() {
                let color = motifColorPalette[idx % motifColorPalette.count]
                for weekIdx in motif.instanceWeekIndices {
                    let startDay = weekIdx * 7
                    guard startDay < totalDays else { continue }
                    for d in startDay..<min(startDay + 7, totalDays) { dayMotifColor[d] = color }
                }
            }
        }

        let bpt = 10 // barsPerTurn
        for child in root.children where child.name.hasPrefix("bar_") {
            guard let model = child as? ModelEntity else { continue }
            let parts = child.name.components(separatedBy: "_")
            guard parts.count >= 3, let barIndex = Int(parts[1]) else { continue }
            let dayIndex = barIndex * 7 / max(1, bpt)

            if let motifColor = dayMotifColor[dayIndex] {
                model.model?.materials = [barMaterial(color: motifColor)]
                model.scale = SIMD3<Float>(1.8, 1.0, 1.8)
            } else if !show {
                model.scale = .one
            }
        }
    }

    static func updateMaterialLOD(root: Entity, totalDays: Int, zoomScale: Float) {
        let hideBars = zoomScale < 0.4
        for child in root.children where child.name.hasPrefix("bar_") {
            child.isEnabled = !hideBars
        }
    }

    enum LODLevel: Equatable { case high, medium, low }
    struct LODTagComponent: Component { var level: LODLevel }
}
