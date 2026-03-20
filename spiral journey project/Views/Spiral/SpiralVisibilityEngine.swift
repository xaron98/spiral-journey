import Foundation
import SpiralKit

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  SpiralVisibilityEngine — single source of truth for spiral rendering  ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// ARCHITECTURE
// ============
// One function — `resolve(...)` — takes the raw view inputs and returns a
// `SpiralRenderState` struct that contains ALL rendering decisions for the
// current frame. No drawing code should make its own visibility decisions.
//
// The engine owns 5 independent subsystems:
//   1. Day visibility     — which days render, with what fade
//   2. Origin visibility  — structural anchor, zoom-dependent
//   3. No-data fallback   — gray placeholder only when truly no data
//   4. Context visibility — work/study blue bands, follows day visibility
//   5. Marker visibility  — accent dots, debug dots (opt-in)
//
// ROOT CAUSES OF PREVIOUS BUGS
// ============================
// Bug 1 (zoom-out spiral vanishes):
//   The old code computed windowEnd as:
//     min(cameraMaxTurn, min(cursorTurns, window.endIndex + 1))
//   When cameraMaxVisibleTurn() returned a value < data range (because
//   the perspective camera's visible horizon shrinks at extreme zoom-out),
//   windowEnd got clipped below lastDayIndex+1. The backbone only draws
//   PAST dataEndTurns, so with data range clipped off, only gray remained.
//
// Bug 2 (zoom-in origin vanishes):
//   Origin was culled by the same visibilityState(for: dayIndex, window:)
//   as normal days. With close zoom the window was e.g. [8..10], so day 0
//   had distance >= visibleCount and was culled. No separate origin path.
//
// Bug 3 (green dot):
//   drawOrigin() unconditionally drew SpiralColors.accent (green/teal)
//   fill + glow at turn 0.
//
// Bug 4 (disappear/reappear dead zone + missing blue bands):
//   computeEffectiveRenderBounds was a PATCH on top of a broken windowEnd
//   calculation. It extended upToTurns to cover data, but the logical
//   VisibleDayWindow (which drives day-level culling and thus context
//   block visibility) was computed INDEPENDENTLY of the render bounds.
//   At certain zoom levels, the render bounds covered data turns but the
//   day window's effectiveActiveIndex was stale or misaligned, causing
//   visibilityState(for:) to cull days that were geometrically rendered.
//   Result: backbone + data glow visible, but day rings, context blocks,
//   and data points hidden because their per-day vis.isVisible was false.
//   This created "spiral appears but blue bands missing" or complete
//   disappear/reappear jumps when a threshold crossed.
//
// FIX: This rebuild eliminates computeEffectiveRenderBounds entirely.
// Instead, the render turn range is derived FROM the VisibleDayWindow,
// which is always valid. The window determines render bounds, not the
// other way around. The camera is advisory only for the backbone tail.

// MARK: - Data Types

/// Bounds of actual recorded data in the spiral.
struct DataDayBounds {
    let firstDayIndex: Int
    let lastDayIndex: Int
    let hasData: Bool
}

/// Per-day rendering state.
struct DayVisibilityState {
    let isVisible: Bool
    let opacity: Double
    let emphasis: Double
    let blur: Double
    let strokeScale: Double
    let distanceFromActive: Int
}

/// Origin (turn 0) visibility — zoom-dependent, independent of day culling.
struct OriginVisibilityState {
    let isVisible: Bool
    let opacity: Double
    let screenRadius: Double
    let emphasis: Double

    // Tunable thresholds
    static let zoomFullVisible: Double = 3.0
    static let zoomFullHidden: Double = 10.0
    static let minScreenRadius: Double = 4.0
    static let defaultScreenRadius: Double = 7.0
}

/// Day window — the trailing range of days that are rendered.
struct VisibleDayWindow {
    let requestedActiveIndex: Int
    let effectiveActiveIndex: Int
    let startIndex: Int
    let endIndex: Int
    let visibleCount: Int
    let clampedToDataBounds: Bool
    /// Raw fractional viewport start — used for smooth edge fading
    /// so the boundary day fades out gradually instead of snapping.
    let viewportFromFractional: Double

    var fromTurns: Double { Double(max(startIndex, 0)) }
    var upToTurns: Double { Double(endIndex) + 1.0 }
}

/// Per-context-block visibility for a given day.
struct ContextDayVisibility {
    let dayIndex: Int
    let isVisible: Bool
    let opacity: Double
}

/// Cursor rendering state — governs whether the cursor dot should draw.
struct CursorRenderState {
    let turnsPosition: Double
    let isInRenderRange: Bool
    let opacity: Double

    /// True when the cursor should actually be drawn.
    var shouldDraw: Bool { isInRenderRange && opacity > 0 }
}

/// Marker rendering flags — opt-in decorative elements.
struct MarkerRenderingState {
    let shouldRenderOriginAccent: Bool
    let shouldRenderOriginDebugDot: Bool
    let shouldRenderContextMarkers: Bool
}

/// Complete rendering state for one frame. Every draw function reads from this.
struct SpiralRenderState {
    let dataBounds: DataDayBounds
    let requestedActiveIndex: Int
    let effectiveActiveIndex: Int
    let visibleWindow: VisibleDayWindow
    let zoom: Double
    /// Turn range to actually draw geometry in. Covers all visible data.
    let renderFromTurns: Double
    let renderUpToTurns: Double
    /// Hard clip for backbone gray path. The backbone (drawn past dataEndTurns)
    /// stops at this value — prevents empty gray spiral ahead of cursor.
    let backboneClipTurns: Double
    /// Turn value where recorded phase data ends. Used by drawSpiralPath to skip
    /// backbone over data, and by drawDataGlow/drawDataPoints for cut logic.
    let dataEndTurns: Double
    /// Cursor dot rendering state (nil when no cursor is present).
    let cursorState: CursorRenderState?
    let originState: OriginVisibilityState
    let markerState: MarkerRenderingState
    let showNoDataFallback: Bool

    /// Get the visibility state for a specific day.
    func dayVisibility(for dayIndex: Int) -> DayVisibilityState {
        SpiralVisibilityEngine.visibilityState(for: dayIndex, window: visibleWindow)
    }

    /// Get context visibility for a day (follows day visibility).
    /// Context blocks only appear on days the cursor has already reached —
    /// they should not be visible ahead of the cursor/vigilia path.
    func contextVisibility(for dayIndex: Int) -> ContextDayVisibility {
        let dv = dayVisibility(for: dayIndex)
        let behindCursor = dayIndex <= requestedActiveIndex
        return ContextDayVisibility(
            dayIndex: dayIndex,
            isVisible: dv.isVisible && markerState.shouldRenderContextMarkers && behindCursor,
            opacity: dv.opacity
        )
    }
}

// MARK: - Engine

/// Pure, stateless visibility engine. All functions are static.
/// Call `resolve(...)` to get a complete `SpiralRenderState` for one frame.
enum SpiralVisibilityEngine {

    // MARK: - Tunable curves

    /// Days 0-5 fully visible, day 6 slight fade, day 7 hard cut.
    static let opacityCurve: [Double] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.4, 0.05]
    static let blurCurve: [Double] = [0, 0, 0.3, 0.6, 1.0, 1.5, 2.0]
    static let strokeScaleCurve: [Double] = [1.0, 0.95, 0.88, 0.80, 0.72, 0.65, 0.58]

    // MARK: - Main resolver

    /// Compute the complete render state for one frame.
    ///
    /// The viewport `[viewportFromTurns, viewportUpToTurns]` is the single
    /// source of truth for what the user sees.  The engine derives fade,
    /// render range, and cursor state from it.
    ///
    /// - `records`: all sleep records
    /// - `cursorAbsHour`: real-time clock position for the cursor dot (nil = no cursor)
    /// - `viewportFromTurns`: near edge of the visible viewport
    /// - `viewportUpToTurns`: far edge of the visible viewport
    /// - `spiralExtentTurns`: total geometry size (growth frontier)
    /// - `spiralPeriod`: hours per turn (typically 24)
    /// - `cameraMaxTurn`: advisory upper limit for backbone tail past data
    /// - `viewportFromTurns/viewportUpToTurns`: data visibility window (which days are visible)
    /// - `cameraFromTurns/cameraUpToTurns`: camera framing window (cursor-centered)
    /// - `backboneCapTurn`: hard cap for backbone gray path (cursor + small tail)
    ///
    /// Render range FROM = min(viewport, camera) so data behind the camera center still renders.
    /// Render range UP TO = min(cameraUpTo, backboneCap) so no empty gray ahead of cursor.
    static func resolve(
        records: [SleepRecord],
        cursorAbsHour: Double? = nil,
        viewportFromTurns: Double,
        viewportUpToTurns: Double,
        cameraFromTurns: Double,
        cameraUpToTurns: Double,
        spiralExtentTurns: Double,
        spiralPeriod: Double,
        cameraMaxTurn: Double,
        backboneCapTurn: Double,
        showAccentMarker: Bool = false,
        showDebugDot: Bool = false,
        showContextMarkers: Bool = true
    ) -> SpiralRenderState {
        let zoom = viewportUpToTurns - viewportFromTurns

        // Active turn position: derived from cursorAbsHour (for opacity anchor only).
        let activeTurns: Double
        if let absHour = cursorAbsHour {
            activeTurns = absHour / max(spiralPeriod, 1.0)
        } else {
            activeTurns = spiralExtentTurns
        }

        // 1. Data bounds
        let bounds = computeDataDayBounds(records)

        // 2. Day window — DERIVED FROM VIEWPORT, not from a separate discrete system.
        //    The viewport is the single source of truth for which days are visible.
        //    The cursor only affects opacity styling, never visibility gating.
        let window = computeVisibleDayWindow(
            activeTurns: activeTurns,
            viewportFromTurns: viewportFromTurns,
            viewportUpToTurns: viewportUpToTurns,
            bounds: bounds
        )

        // 3. Render turn range.
        //    FROM = min(viewport, camera) so data behind cursor still renders.
        //    UP TO = min(camera + margin, backboneCap) so no gray excess ahead.
        let renderRange = computeRenderTurnRange(
            cameraFrom: cameraFromTurns,
            cameraUpTo: cameraUpToTurns,
            viewportFrom: viewportFromTurns,
            backboneCapTurn: backboneCapTurn,
            cameraMaxTurn: cameraMaxTurn
        )

        // 4. Origin visibility (zoom-only)
        let origin = computeOriginVisibility(hasData: bounds.hasData, zoom: zoom)

        // 5. Markers
        let markers = MarkerRenderingState(
            shouldRenderOriginAccent: showAccentMarker,
            shouldRenderOriginDebugDot: showDebugDot,
            shouldRenderContextMarkers: showContextMarkers
        )

        // 6. No-data fallback
        let showFallback = shouldShowNoDataFallback(bounds: bounds, window: window)

        // 7. Data end turns
        let dataEnd = computeDataEndTurns(records: records, spiralPeriod: spiralPeriod)

        // 8. Cursor state
        let cursor: CursorRenderState? = computeCursorState(
            cursorAbsHour: cursorAbsHour,
            spiralPeriod: spiralPeriod,
            renderFrom: renderRange.from,
            renderUpTo: renderRange.upTo
        )

        return SpiralRenderState(
            dataBounds: bounds,
            requestedActiveIndex: window.requestedActiveIndex,
            effectiveActiveIndex: window.effectiveActiveIndex,
            visibleWindow: window,
            zoom: zoom,
            renderFromTurns: renderRange.from,
            renderUpToTurns: renderRange.upTo,
            backboneClipTurns: renderRange.backboneClip,
            dataEndTurns: dataEnd,
            cursorState: cursor,
            originState: origin,
            markerState: markers,
            showNoDataFallback: showFallback
        )
    }

    // MARK: - Data bounds

    static func computeDataDayBounds(_ records: [SleepRecord]) -> DataDayBounds {
        var first = Int.max
        var last  = Int.min
        for record in records where !record.phases.isEmpty {
            if record.day < first { first = record.day }
            if record.day > last  { last  = record.day }
        }
        let hasData = first <= last
        return DataDayBounds(
            firstDayIndex: hasData ? first : 0,
            lastDayIndex:  hasData ? last  : 0,
            hasData: hasData
        )
    }

    // MARK: - Day window (viewport-derived)

    /// Compute the visible day window DIRECTLY from the viewport turn range.
    /// The viewport is the single source of truth. Every day whose turn range
    /// overlaps [viewportFromTurns, viewportUpToTurns] is visible.
    /// The cursor position (activeTurns) only affects opacity styling.
    static func computeVisibleDayWindow(
        activeTurns: Double,
        viewportFromTurns: Double,
        viewportUpToTurns: Double,
        bounds: DataDayBounds
    ) -> VisibleDayWindow {
        let requestedActiveIndex = Int(floor(activeTurns))
        // Opacity anchor: clamp to lastDayIndex so data near the cursor stays
        // bright. The WINDOW (startIndex/endIndex) controls which days are
        // visible — when cursor advances 7+ turns past data, the window
        // excludes all data days and they disappear. But while data IS in the
        // window, effectiveActive keeps it at high opacity.
        let effectiveActive: Int
        let clamped: Bool
        if bounds.hasData && requestedActiveIndex > bounds.lastDayIndex {
            effectiveActive = bounds.lastDayIndex
            clamped = true
        } else {
            effectiveActive = requestedActiveIndex
            clamped = false
        }

        // Day range derived from viewport — a day is included if ANY part
        // of its [day, day+1) turn range overlaps the viewport.
        let startIndex = max(0, Int(floor(viewportFromTurns)))
        let endIndex   = max(startIndex, Int(floor(viewportUpToTurns)))
        let count = endIndex - startIndex + 1

        return VisibleDayWindow(
            requestedActiveIndex: requestedActiveIndex,
            effectiveActiveIndex: effectiveActive,
            startIndex: startIndex,
            endIndex: endIndex,
            visibleCount: count,
            clampedToDataBounds: clamped,
            viewportFromFractional: viewportFromTurns
        )
    }

    // MARK: - Per-day visibility (single distance from cursor)

    /// Returns styling state for a day based on distance from the CURSOR.
    ///
    /// Uses ONE distance source only (requestedActiveIndex = actual cursor position).
    /// This guarantees MONOTONIC fade: day closest to cursor = brightest,
    /// day furthest = dimmest. No exceptions. No clamping to data bounds.
    ///
    /// - Distance 0-5: full opacity (1.0) from opacityCurve
    /// - Distance 6: slight fade (0.4)
    /// - Distance 7: near invisible (0.05)
    /// - Distance 8+: exponential decay toward 0
    static func visibilityState(for dayIndex: Int, window: VisibleDayWindow) -> DayVisibilityState {
        // Single distance: from the actual cursor position. Period.
        let dist = abs(window.requestedActiveIndex - dayIndex)

        let rawOpacity: Double
        if dist < opacityCurve.count {
            rawOpacity = opacityCurve[dist]
        } else {
            let base = opacityCurve.last ?? 0.05
            let extra = dist - opacityCurve.count + 1
            rawOpacity = base * pow(0.15, Double(extra))
        }

        let blur: Double = dist < blurCurve.count ? blurCurve[dist] : (blurCurve.last ?? 2.0)
        let strokeScale: Double = dist < strokeScaleCurve.count ? strokeScaleCurve[dist] : (strokeScaleCurve.last ?? 0.58)

        guard rawOpacity > 0.01 else {
            return DayVisibilityState(
                isVisible: false, opacity: 0, emphasis: 0,
                blur: 0, strokeScale: 0, distanceFromActive: dist
            )
        }

        return DayVisibilityState(
            isVisible: true, opacity: rawOpacity, emphasis: rawOpacity,
            blur: blur, strokeScale: strokeScale, distanceFromActive: dist
        )
    }

    // MARK: - Render turn range

    /// Compute the turn range to draw and the backbone clip point.
    ///
    /// FROM = min(cameraFrom, viewportFrom) - margin.
    ///   → Data behind the camera center still renders if in the data window.
    /// UP TO = cameraUpTo + margin, capped by camera horizon.
    ///   → Covers all data the camera can see. NOT clipped by backbone cap.
    /// BACKBONE CLIP = backboneCapTurn (cursor + tiny tail).
    ///   → Only affects drawSpiralPath, not data points/glow.
    static func computeRenderTurnRange(
        cameraFrom: Double,
        cameraUpTo: Double,
        viewportFrom: Double,
        backboneCapTurn: Double,
        cameraMaxTurn: Double
    ) -> (from: Double, upTo: Double, backboneClip: Double) {
        let edgeMargin = 0.25

        // FROM: reach back to whichever is earliest — camera or data window.
        let from = max(min(cameraFrom, viewportFrom) - edgeMargin, 0)

        // UP TO: camera window edge + margin. NOT capped by backbone.
        // This ensures all data within the camera view gets rendered.
        var upTo = min(cameraUpTo + edgeMargin, cameraMaxTurn)

        // Safety: non-degenerate range.
        if upTo < from + 0.1 {
            upTo = from + 1.0
        }

        // Backbone clip: exact cap. Only the gray path respects this.
        let backboneClip = backboneCapTurn

        return (from: from, upTo: upTo, backboneClip: backboneClip)
    }

    // MARK: - Cursor state

    /// Compute cursor rendering state from the absolute hour position.
    /// Returns nil when no cursor is present (cursorAbsHour is nil).
    static func computeCursorState(
        cursorAbsHour: Double?,
        spiralPeriod: Double,
        renderFrom: Double,
        renderUpTo: Double
    ) -> CursorRenderState? {
        guard let absHour = cursorAbsHour else { return nil }
        let period = max(spiralPeriod, 1.0)
        let turns = absHour / period
        let inRange = turns >= renderFrom && turns <= renderUpTo
        // Full opacity when in range, zero when outside
        let opacity = inRange ? 1.0 : 0.0
        return CursorRenderState(
            turnsPosition: turns,
            isInRenderRange: inRange,
            opacity: opacity
        )
    }

    // MARK: - Data end turns

    /// Compute the spiral turn value where recorded phase data ends.
    /// Uses the same day+offset formula as drawDataPoints: turns = day + hour/period.
    static func computeDataEndTurns(records: [SleepRecord], spiralPeriod: Double) -> Double {
        guard !records.isEmpty else { return 0.0 }
        let period = max(spiralPeriod, 1.0)
        var best = 0.0
        for r in records {
            let endH: Double
            if let lastSleep = r.phases.last(where: { $0.phase != .awake }) {
                endH = lastSleep.hour + 0.25
            } else {
                endH = r.wakeupHour
            }
            let t = Double(r.day) + endH / period
            if t > best { best = t }
        }
        return best
    }

    // MARK: - Origin visibility

    static func computeOriginVisibility(
        hasData: Bool,
        zoom: Double
    ) -> OriginVisibilityState {
        guard hasData else {
            return OriginVisibilityState(
                isVisible: false, opacity: 0, screenRadius: 0, emphasis: 0
            )
        }

        let lo = OriginVisibilityState.zoomFullVisible
        let hi = OriginVisibilityState.zoomFullHidden

        let opacity: Double
        if zoom <= lo {
            opacity = 1.0
        } else if zoom >= hi {
            opacity = 0.0
        } else {
            opacity = 1.0 - (zoom - lo) / (hi - lo)
        }

        guard opacity > 0 else {
            return OriginVisibilityState(
                isVisible: false, opacity: 0, screenRadius: 0, emphasis: 0
            )
        }

        let zoomAttenuation = min(1.0, max(0.3, 3.0 / max(zoom, 0.5)))
        let screenRadius = max(
            OriginVisibilityState.minScreenRadius,
            OriginVisibilityState.defaultScreenRadius * zoomAttenuation
        )

        return OriginVisibilityState(
            isVisible: true, opacity: opacity,
            screenRadius: screenRadius, emphasis: opacity
        )
    }

    // MARK: - No-data fallback

    /// True ONLY when there is genuinely no renderable data.
    /// If `bounds.hasData == true`, the window clamping guarantees this returns false.
    static func shouldShowNoDataFallback(bounds: DataDayBounds, window: VisibleDayWindow) -> Bool {
        // Gray fallback ONLY when the user has zero data.
        // When data exists but is outside the current 7-turn window,
        // the normal pipeline handles it: backbone draws, data arcs
        // are simply skipped by isVisible checks. No fallback needed.
        return !bounds.hasData
    }

    // MARK: - Debug diagnostics

    /// Returns a multi-line diagnostic string for the current render state.
    static func diagnostics(_ state: SpiralRenderState) -> String {
        var lines: [String] = []
        lines.append("[SpiralVis] data=[\(state.dataBounds.firstDayIndex)…\(state.dataBounds.lastDayIndex)] hasData=\(state.dataBounds.hasData)")
        lines.append("[SpiralVis] requested=\(state.requestedActiveIndex) effective=\(state.effectiveActiveIndex) zoom=\(String(format: "%.2f", state.zoom))")
        lines.append("[SpiralVis] window=[\(state.visibleWindow.startIndex)…\(state.visibleWindow.endIndex)] count=\(state.visibleWindow.visibleCount) clamped=\(state.visibleWindow.clampedToDataBounds)")
        lines.append("[SpiralVis] render=\(String(format: "%.1f", state.renderFromTurns))…\(String(format: "%.1f", state.renderUpToTurns))")
        lines.append("[SpiralVis] origin=\(state.originState.isVisible ? "visible@\(String(format: "%.2f", state.originState.opacity))" : "hidden") zoom thresholds: show≤\(OriginVisibilityState.zoomFullVisible) hide≥\(OriginVisibilityState.zoomFullHidden)")
        lines.append("[SpiralVis] fallback=\(state.showNoDataFallback) accent=\(state.markerState.shouldRenderOriginAccent) context=\(state.markerState.shouldRenderContextMarkers)")

        // Count visible data days
        if state.dataBounds.hasData {
            let visibleDataDays = (state.dataBounds.firstDayIndex...state.dataBounds.lastDayIndex).filter {
                state.dayVisibility(for: $0).isVisible
            }.count
            lines.append("[SpiralVis] visibleDataDays=\(visibleDataDays)/\(state.dataBounds.lastDayIndex - state.dataBounds.firstDayIndex + 1)")
        }

        return lines.joined(separator: "\n")
    }
}
