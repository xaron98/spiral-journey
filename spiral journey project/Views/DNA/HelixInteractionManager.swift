import SwiftUI
import RealityKit

/// Manages rotation, zoom, selection, and auto-rotation state for the 3D helix view.
@available(iOS 18.0, *)
@Observable
@MainActor
final class HelixInteractionManager {

    // MARK: - Rotation

    /// Cumulative rotation around the Y axis (horizontal drag).
    var rotationY: Float = 0
    /// Cumulative rotation around the X axis (vertical drag).
    var rotationX: Float = 0

    // MARK: - Zoom

    /// Current magnification scale, clamped to [0.5, 3.0].
    var zoomScale: Float = 1.0

    // MARK: - Selection

    /// Currently selected week index, or nil.
    var selectedWeek: Int? = nil

    // MARK: - Motif Toggle

    /// Whether motif region highlights are visible.
    var showPatterns: Bool = false

    // MARK: - Interaction State

    /// True while the user is dragging or pinching; pauses auto-rotation.
    var isInteracting: Bool = false

    // MARK: - Auto-rotation

    /// Radians per tick for idle auto-rotation.
    private let autoRotationSpeed: Float = 0.003

    /// Advance auto-rotation by one frame tick.
    func tickAutoRotation() {
        guard !isInteracting else { return }
        rotationY += autoRotationSpeed
    }

    // MARK: - Computed Transform

    /// Combined transform from rotation + zoom, suitable for the helix root entity.
    var sceneTransform: Transform {
        let scaleVec = SIMD3<Float>(repeating: zoomScale)
        let rotY = simd_quatf(angle: rotationY, axis: SIMD3<Float>(0, 1, 0))
        let rotX = simd_quatf(angle: rotationX, axis: SIMD3<Float>(1, 0, 0))
        let combined = rotY * rotX
        return Transform(scale: scaleVec, rotation: combined, translation: .zero)
    }

    // MARK: - Gesture Helpers

    /// Apply a drag delta to rotation.
    func applyDrag(translationX: Float, translationY: Float) {
        let sensitivity: Float = 0.008
        rotationY += translationX * sensitivity
        rotationX -= translationY * sensitivity
        // Clamp X rotation to avoid flipping
        rotationX = max(-.pi / 2.5, min(.pi / 2.5, rotationX))
    }

    /// Apply a magnification value from MagnifyGesture.
    func applyZoom(_ magnification: Float) {
        zoomScale = max(0.5, min(3.0, magnification))
    }

    /// Select a week from a tapped entity name (e.g. "nucleotide_1_42" -> week 6).
    /// Returns the selected week if parsing succeeds.
    @discardableResult
    func selectFromEntityName(_ name: String) -> Int? {
        // Expected format: "nucleotide_STRAND_DAY"
        let parts = name.split(separator: "_")
        guard parts.count >= 3,
              parts[0] == "nucleotide",
              let dayIndex = Int(parts[2]) else {
            return nil
        }
        let week = dayIndex / 7
        if selectedWeek == week {
            selectedWeek = nil  // toggle off
        } else {
            selectedWeek = week
        }
        return selectedWeek
    }
}
