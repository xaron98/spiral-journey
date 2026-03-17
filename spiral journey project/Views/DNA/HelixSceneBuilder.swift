import RealityKit
import SwiftUI
import SpiralKit

/// Builds a RealityKit entity tree representing a double-helix Sleep DNA visualization.
///
/// The helix axis is vertical (Y-up). One full turn = 7 days (1 week).
/// Strand 1 (purple) encodes sleep features; strand 2 (orange) encodes context features.
/// Nucleotides are spheres colored by sleep quality; base pairs are thin connectors between strands.
@available(iOS 18.0, *)
enum HelixSceneBuilder {

    // MARK: - Constants

    /// Vertical distance per day.
    private static let zStep: Float = 0.06
    /// Base helix radius.
    private static let baseRadius: Float = 0.25
    /// Scale multiplier applied to DayHelixParams.helixRadius.
    private static let radiusScale: Float = 0.12
    /// Sphere radius for nucleotide nodes.
    private static let nucleotideRadius: Float = 0.015
    /// Strand tube radius (connects consecutive nucleotides on the same strand).
    private static let strandTubeRadius: Float = 0.005
    /// Base-pair connector radius.
    private static let basePairRadius: Float = 0.003
    /// Motif highlight cylinder radius.
    private static let motifCylinderRadius: Float = 0.008

    // MARK: - Colors

    private static let strand1Color: UIColor = UIColor(Color(hex: "7c3aed"))  // purple
    private static let strand2Color: UIColor = UIColor(Color(hex: "f59e0b"))  // orange
    private static let basePairColor: UIColor = UIColor(white: 1.0, alpha: 0.2)
    private static let highlightColor: UIColor = UIColor(Color(hex: "22d3ee"))  // cyan

    // MARK: - Build

    /// Build the full helix scene from a SleepDNA profile.
    /// - Returns: A root `Entity` containing all helix geometry.
    static func build(from profile: SleepDNAProfile) -> Entity {
        let root = Entity()
        root.name = "helix_root"

        let nucleotides = profile.nucleotides
        let geometry = profile.helixGeometry
        let totalDays = nucleotides.count
        guard totalDays > 0 else { return root }

        let yOffset = Float(totalDays - 1) * zStep / 2.0

        // Build lookup for geometry params by day
        var geomByDay: [Int: DayHelixParams] = [:]
        for g in geometry { geomByDay[g.day] = g }

        // Previous positions for strand tubes
        var prevPos1: SIMD3<Float>?
        var prevPos2: SIMD3<Float>?

        for (index, nuc) in nucleotides.enumerated() {
            let dayIndex = index
            let t = Float(dayIndex) / 7.0  // turns
            let theta = t * 2 * .pi

            let params = geomByDay[nuc.day]
            let helixR = params.map { Float($0.helixRadius) } ?? 0.5
            let twist = params.map { Float($0.twistAngle) } ?? 0.0

            let r = baseRadius + helixR * radiusScale
            let y = Float(dayIndex) * zStep - yOffset

            // Strand 1 position
            let pos1 = SIMD3<Float>(r * cos(theta), y, r * sin(theta))
            // Strand 2 position (opposite side + twist offset)
            let pos2 = SIMD3<Float>(
                r * cos(theta + .pi + twist),
                y,
                r * sin(theta + .pi + twist)
            )

            // Sleep quality color (feature index 15): green (good) -> red (poor)
            let quality = Float(nuc[.sleepQuality])
            let nucColor = qualityColor(quality)

            // --- Nucleotide spheres ---
            let sphere1 = nucleotideSphere(color: strand1Color, radius: nucleotideRadius)
            sphere1.name = "nucleotide_1_\(dayIndex)"
            sphere1.position = pos1
            root.addChild(sphere1)

            let sphere2 = nucleotideSphere(color: nucColor, radius: nucleotideRadius)
            sphere2.name = "nucleotide_2_\(dayIndex)"
            sphere2.position = pos2
            root.addChild(sphere2)

            // --- Base pair connector ---
            let pair = basePairConnector(from: pos1, to: pos2)
            pair.name = "basepair_\(dayIndex)"
            root.addChild(pair)

            // --- Strand tubes (connect to previous nucleotide) ---
            if let prev1 = prevPos1 {
                let tube1 = strandTube(from: prev1, to: pos1, color: strand1Color)
                tube1.name = "strand1_seg_\(dayIndex)"
                root.addChild(tube1)
            }
            if let prev2 = prevPos2 {
                let tube2 = strandTube(from: prev2, to: pos2, color: strand2Color)
                tube2.name = "strand2_seg_\(dayIndex)"
                root.addChild(tube2)
            }

            prevPos1 = pos1
            prevPos2 = pos2
        }

        return root
    }

    // MARK: - Highlight Similar Weeks

    /// Highlight nucleotides belonging to weeks similar to the selected one.
    static func highlightSimilarWeeks(
        root: Entity,
        selectedWeek: Int,
        alignments: [WeekAlignment],
        totalDays: Int
    ) {
        // Find alignments above threshold
        let threshold: Double = 0.5
        let similarWeeks = alignments
            .filter { $0.similarity >= threshold && $0.weekIndex != selectedWeek }
            .map(\.weekIndex)
        let allHighlightWeeks = Set(similarWeeks + [selectedWeek])

        let highlightMaterial = SimpleMaterial(
            color: highlightColor,
            roughness: 0.3,
            isMetallic: true
        )

        for day in 0..<totalDays {
            let week = day / 7
            guard allHighlightWeeks.contains(week) else { continue }
            for strand in 1...2 {
                let name = "nucleotide_\(strand)_\(day)"
                if let entity = root.findEntity(named: name),
                   var model = entity.components[ModelComponent.self] {
                    model.materials = [highlightMaterial]
                    entity.components[ModelComponent.self] = model
                }
            }
        }
    }

    // MARK: - Reset Highlights

    /// Restore all nucleotides to their default colors.
    static func resetHighlights(root: Entity, totalDays: Int) {
        let strand1Mat = SimpleMaterial(
            color: strand1Color,
            roughness: 0.5,
            isMetallic: false
        )

        for day in 0..<totalDays {
            // Strand 1: always purple
            let name1 = "nucleotide_1_\(day)"
            if let entity = root.findEntity(named: name1),
               var model = entity.components[ModelComponent.self] {
                model.materials = [strand1Mat]
                entity.components[ModelComponent.self] = model
            }

            // Strand 2: restore by name — we store quality in the entity itself
            // Since we can't easily retrieve original quality, re-apply orange
            let name2 = "nucleotide_2_\(day)"
            if let entity = root.findEntity(named: name2),
               var model = entity.components[ModelComponent.self] {
                let mat = SimpleMaterial(
                    color: strand2Color,
                    roughness: 0.5,
                    isMetallic: false
                )
                model.materials = [mat]
                entity.components[ModelComponent.self] = model
            }
        }
    }

    // MARK: - Toggle Motif Regions

    /// Show or hide translucent cylinders around weeks belonging to motifs.
    static func toggleMotifRegions(
        root: Entity,
        motifs: [SleepMotif],
        show: Bool,
        totalDays: Int,
        yOffset: Float? = nil
    ) {
        let computedYOffset = yOffset ?? (Float(totalDays - 1) * zStep / 2.0)

        // Remove any existing motif entities first
        let existing = root.children.filter { $0.name.hasPrefix("motif_") }
        for entity in existing {
            root.removeChild(entity)
        }

        guard show else { return }

        // Color palette for different motifs
        let motifColors: [UIColor] = [
            UIColor(Color(hex: "22d3ee")),  // cyan
            UIColor(Color(hex: "a78bfa")),  // violet
            UIColor(Color(hex: "34d399")),  // emerald
            UIColor(Color(hex: "fb923c")),  // orange
        ]

        for (motifIdx, motif) in motifs.enumerated() {
            let color = motifColors[motifIdx % motifColors.count]

            for weekIdx in motif.instanceWeekIndices {
                let startDay = weekIdx * 7
                let endDay = min(startDay + 6, totalDays - 1)
                guard startDay < totalDays else { continue }

                let yStart = Float(startDay) * zStep - computedYOffset
                let yEnd = Float(endDay) * zStep - computedYOffset
                let height = abs(yEnd - yStart) + zStep
                let midY = (yStart + yEnd) / 2.0

                let mesh = MeshResource.generateCylinder(
                    height: height,
                    radius: baseRadius + radiusScale + 0.02
                )
                var material = SimpleMaterial(
                    color: color.withAlphaComponent(0.15),
                    roughness: 0.8,
                    isMetallic: false
                )
                material.color.tint = color.withAlphaComponent(0.15)
                let cylinder = ModelEntity(mesh: mesh, materials: [material])
                cylinder.name = "motif_\(motif.id.uuidString)_\(weekIdx)"
                cylinder.position = SIMD3<Float>(0, midY, 0)
                root.addChild(cylinder)
            }
        }
    }

    // MARK: - Private Helpers

    /// Create a nucleotide sphere entity.
    private static func nucleotideSphere(color: UIColor, radius: Float) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Create a thin cylinder connecting two strand positions (base pair).
    private static func basePairConnector(from a: SIMD3<Float>, to b: SIMD3<Float>) -> ModelEntity {
        let diff = b - a
        let length = simd_length(diff)
        guard length > 0.001 else {
            return ModelEntity()
        }

        let mesh = MeshResource.generateCylinder(height: length, radius: basePairRadius)
        let material = SimpleMaterial(
            color: basePairColor,
            roughness: 0.8,
            isMetallic: false
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Position at midpoint
        let mid = (a + b) / 2
        entity.position = mid

        // Orient cylinder along the a->b direction
        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(diff)
        entity.transform.rotation = simd_quatf(from: up, to: dir)

        return entity
    }

    /// Create a thin tube connecting consecutive nucleotides on one strand.
    private static func strandTube(
        from a: SIMD3<Float>,
        to b: SIMD3<Float>,
        color: UIColor
    ) -> ModelEntity {
        let diff = b - a
        let length = simd_length(diff)
        guard length > 0.001 else {
            return ModelEntity()
        }

        let mesh = MeshResource.generateCylinder(height: length, radius: strandTubeRadius)
        let material = SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        let mid = (a + b) / 2
        entity.position = mid

        let up = SIMD3<Float>(0, 1, 0)
        let dir = normalize(diff)
        entity.transform.rotation = simd_quatf(from: up, to: dir)

        return entity
    }

    /// Map sleep quality [0, 1] to a color: red (0) -> yellow (0.5) -> green (1).
    private static func qualityColor(_ q: Float) -> UIColor {
        let clamped = max(0, min(1, q))
        let r: Float = clamped < 0.5 ? 1.0 : 1.0 - (clamped - 0.5) * 2.0
        let g: Float = clamped < 0.5 ? clamped * 2.0 : 1.0
        let b: Float = 0.15
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
    }
}
