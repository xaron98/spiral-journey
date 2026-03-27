import Foundation
import RealityKit
import QuartzCore

/// Manages rotation, zoom, and 4D angle state for the Clifford torus 3D view.
///
/// All transform state is @ObservationIgnored — updated at 60fps via CADisplayLink,
/// completely bypassing SwiftUI's update: cycle. Only `selectedEpochIndex` triggers
/// SwiftUI re-renders (for overlays).
@available(iOS 18.0, *)
@Observable
@MainActor
final class NeuroSpiralTorusInteractionManager {

    // MARK: - Entity reference (set once from RealityView make:)

    @ObservationIgnored weak var rootEntity: Entity?

    // MARK: - Rotation (NOT observed — 60fps via CADisplayLink)

    @ObservationIgnored var rotationX: Float = 0.3
    @ObservationIgnored var rotationY: Float = 0.0

    // MARK: - Zoom (NOT observed)

    @ObservationIgnored var zoomScale: Float = 1.0

    // MARK: - 4D Angle (NOT observed — slider updates directly)

    @ObservationIgnored var w4DAngle: Float = 0.8

    // MARK: - Interaction State (NOT observed)

    @ObservationIgnored var isInteracting: Bool = false
    /// Accumulated drag translation — stored here to avoid @State re-renders.
    @ObservationIgnored var dragStart: CGSize = .zero
    /// Baseline zoom before current pinch gesture.
    @ObservationIgnored var baseZoom: Float = 1.0

    // MARK: - Selection (observed — SwiftUI needs this for overlays)

    var selectedEpochIndex: Int? = nil

    // MARK: - Display Link

    @ObservationIgnored private var displayLink: CADisplayLink?
    private let autoRotationSpeed: Float = 0.002

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick() {
        // Auto-rotate when idle
        if !isInteracting {
            rotationY += autoRotationSpeed
        }
        // Apply transform directly to entity — no SwiftUI involved
        rootEntity?.transform = sceneTransform
    }

    // MARK: - Computed Transform

    private var sceneTransform: Transform {
        let scaleVec = SIMD3<Float>(repeating: zoomScale)
        let rotY = simd_quatf(angle: rotationY, axis: SIMD3<Float>(0, 1, 0))
        let rotX = simd_quatf(angle: rotationX, axis: SIMD3<Float>(1, 0, 0))
        let combined = rotY * rotX
        return Transform(scale: scaleVec, rotation: combined, translation: .zero)
    }

    // MARK: - Gesture Helpers

    func applyDrag(translationX: Float, translationY: Float) {
        let sensitivity: Float = 0.008
        rotationY += translationX * sensitivity
        rotationX += translationY * sensitivity
        rotationX = max(-.pi / 2, min(.pi / 2, rotationX))
        // No need to notify SwiftUI — displayLink applies transform next frame
    }

    deinit {
        displayLink?.invalidate()
    }
}
