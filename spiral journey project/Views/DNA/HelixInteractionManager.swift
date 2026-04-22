import SwiftUI
import RealityKit

/// Manages rotation, zoom, selection, and auto-rotation state for the 3D helix view.
///
/// Rotation and zoom are @ObservationIgnored — they update the entity directly
/// via a CADisplayLink at 60fps, completely bypassing SwiftUI's update: cycle.
/// Only selectedWeek and showPatterns trigger SwiftUI re-renders (for overlays).
@available(iOS 18.0, *)
@Observable
@MainActor
final class HelixInteractionManager {

    // MARK: - Entity reference (set once from RealityView make:)

    @ObservationIgnored weak var rootEntity: Entity?

    // MARK: - Rotation (NOT observed)

    @ObservationIgnored var rotationY: Float = 0
    @ObservationIgnored var rotationX: Float = 0

    // MARK: - Zoom (NOT observed)

    @ObservationIgnored var zoomScale: Float = 1.6

    // MARK: - Selection (observed — SwiftUI needs this for overlays)

    var selectedWeek: Int? = nil
    /// Selected bar slot index for phase tooltip (observed — triggers overlay update).
    var selectedSlot: Int? = nil

    // MARK: - Motif Toggle (observed — SwiftUI needs this for legend)

    var showPatterns: Bool = false

    // MARK: - Interaction State

    @ObservationIgnored var isInteracting: Bool = false
    /// Accumulated drag translation — stored here to avoid @State re-renders.
    @ObservationIgnored var dragStart: CGSize = .zero
    /// Baseline zoom before current pinch gesture.
    @ObservationIgnored var baseZoom: Float = 1.6

    // MARK: - Display Link

    #if os(macOS)
    @ObservationIgnored private var displayTimer: Timer?
    #else
    @ObservationIgnored private var displayLink: CADisplayLink?
    #endif
    private let autoRotationSpeed: Float = 0.003

    func startDisplayLink() {
        #if os(macOS)
        guard displayTimer == nil else { return }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        #else
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        #endif
    }

    func stopDisplayLink() {
        #if os(macOS)
        displayTimer?.invalidate()
        displayTimer = nil
        #else
        displayLink?.invalidate()
        displayLink = nil
        #endif
    }

    private func tick() {
        if !isInteracting { rotationY += autoRotationSpeed }
        rootEntity?.transform = sceneTransform
    }

    #if !os(macOS)
    @objc private func displayLinkTick() { tick() }
    #endif

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
        // Sign convention: the model should follow the finger.
        // - Drag right → model visually rotates right (so `rotationY`
        //   decreases, since RealityKit's right-handed +Y axis rotates
        //   CCW as seen from above, which moves the visible face left
        //   for a positive angle).
        // - Drag down → you should end up looking more at the top of
        //   the helix; that requires a negative rotation around +X.
        rotationY -= translationX * sensitivity
        rotationX -= translationY * sensitivity
        rotationX = max(-.pi / 2.5, min(.pi / 2.5, rotationX))
        // No need to notify SwiftUI — displayLink applies transform next frame
    }

    func applyZoom(_ magnification: Float) {
        zoomScale = max(0.5, min(3.0, magnification))
    }

    @discardableResult
    func selectFromEntityName(_ name: String) -> Int? {
        let parts = name.split(separator: "_")
        guard parts.count >= 3,
              parts[0] == "nucleotide",
              let dayIndex = Int(parts[2]) else {
            return nil
        }
        let week = dayIndex / 7
        if selectedWeek == week {
            selectedWeek = nil
        } else {
            selectedWeek = week
        }
        return selectedWeek
    }
}
