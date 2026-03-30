import SwiftUI
import SpiralKit

/// Manages cursor, camera, zoom, and gesture state for the spiral view.
///
/// High-frequency properties (cursor position, camera center, zoom, gesture
/// tracking) are `@ObservationIgnored` — they change on every gesture frame
/// or camera tick and must NOT trigger SwiftUI body re-evaluation.
///
/// Only `needsCanvasRedraw` is observed: the Canvas reads it to know when to
/// redraw, and the manager sets it whenever any rendering-relevant property
/// changes.
@Observable
@MainActor
final class SpiralInteractionManager {

    // MARK: - Observable (triggers SwiftUI / Canvas redraw)

    /// Toggled to signal that the Canvas should redraw.
    /// Read by the Canvas; set by `markDirty()`.
    var needsCanvasRedraw: Bool = false

    // MARK: - Cursor (NOT observed)

    /// Cursor position in absolute hours from start date.
    @ObservationIgnored var cursorAbsHour: Double = 0

    /// True when the cursor tracks real-world time automatically.
    /// Set to false when the user drags the cursor to a past hour.
    @ObservationIgnored var isCursorLive: Bool = true

    /// Maximum turns the spiral has ever reached (drives extent).
    @ObservationIgnored var maxReachedTurns: Double = 1.0

    // MARK: - Camera follow (NOT observed)

    /// Smoothed camera center in turns — the value SpiralView actually uses.
    @ObservationIgnored var smoothCameraCenterTurns: Double = 0

    // MARK: - Zoom (NOT observed)

    /// Committed zoom level after pinch ends.
    @ObservationIgnored var visibleDays: Double = 1

    /// Live zoom level during pinch (interpolates toward visibleDays).
    @ObservationIgnored var liveVisibleDays: Double = 1

    /// Baseline visible days at pinch start.
    @ObservationIgnored var pinchBaseVisibleDays: Double = 1

    /// Normalised zoom slider value [0,1] in log-space.
    @ObservationIgnored var zoomNorm: Double = 1.0

    // MARK: - Gesture tracking (NOT observed)

    /// True while a drag or pinch gesture is physically active.
    @ObservationIgnored var isUserInteracting: Bool = false

    /// Interaction type for lerp decisions.
    enum InteractionMode: String { case none, scrub, pinch }
    @ObservationIgnored var interactionMode: InteractionMode = .none

    /// Timestamp of the last gesture event — used for post-gesture decay.
    @ObservationIgnored var lastInteractionTime: Date = .distantPast

    /// Previous drag location for tangent-based cursor advancement.
    @ObservationIgnored var dragPrevLocation: CGPoint = .zero

    /// True on the first touch of a new drag — triggers snap via nearestHour.
    @ObservationIgnored var dragIsNew: Bool = true

    /// True once the pinch gesture has started (used for one-shot base capture).
    @ObservationIgnored var pinchStarted: Bool = false

    // MARK: - Camera follow task handle

    @ObservationIgnored private var cameraFollowTask: Task<Void, Never>?
    @ObservationIgnored private var cursorAdvanceTask: Task<Void, Never>?

    // MARK: - Dirty tracking

    /// Call after changing any rendering-relevant property.
    /// Toggles `needsCanvasRedraw` so the Canvas picks up the change.
    func markDirty() {
        needsCanvasRedraw.toggle()
    }

    // MARK: - Camera follow loop

    /// Starts the smooth camera follow loop (~30fps).
    /// Lerps `smoothCameraCenterTurns` toward `cursorAbsHour / period`.
    /// During scrub gestures the lerp is suppressed (gesture handler owns the value).
    /// After gesture ends the lerp ramps up smoothly over ~0.5s.
    func startCameraFollow(period: @escaping @MainActor () -> Double) {
        cameraFollowTask?.cancel()
        cameraFollowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }

                let p = period()
                guard p > 0 else { continue }
                let cursorTurns = self.cursorAbsHour / p

                if self.isUserInteracting && self.interactionMode == .scrub {
                    // During scrub: camera is set directly in gesture handler.
                } else {
                    let timeSinceGesture = Date().timeIntervalSince(self.lastInteractionTime)
                    let lerpFactor: Double
                    if self.isUserInteracting && self.interactionMode == .pinch {
                        lerpFactor = 0.08
                    } else if timeSinceGesture < 0.5 {
                        let t = timeSinceGesture / 0.5
                        lerpFactor = 0.05 + t * 0.20
                    } else {
                        lerpFactor = 0.25
                    }
                    let delta = cursorTurns - self.smoothCameraCenterTurns
                    if abs(delta) > 0.0001 {
                        self.smoothCameraCenterTurns += delta * lerpFactor
                        self.markDirty()
                    }
                }
            }
        }
    }

    /// Starts a background task that advances the cursor every 60 seconds
    /// to track real-world time (only when cursor is live and not interacting).
    func startCursorAdvance(startDate: @escaping @MainActor () -> Date) {
        cursorAdvanceTask?.cancel()
        cursorAdvanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                guard self.isCursorLive, !self.isUserInteracting else { continue }
                self.cursorAbsHour = Date().timeIntervalSince(startDate()) / 3600
                self.markDirty()
            }
        }
    }

    /// Stops the camera follow and cursor advance loops.
    func stopLoops() {
        cameraFollowTask?.cancel()
        cameraFollowTask = nil
        cursorAdvanceTask?.cancel()
        cursorAdvanceTask = nil
    }

    deinit {
        cameraFollowTask?.cancel()
        cursorAdvanceTask?.cancel()
    }
}
