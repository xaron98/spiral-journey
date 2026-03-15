import Testing
import Foundation
@testable import SpiralKit
@testable import spiral_journey_project
// SpiralVisibilityEngine lives in the main app target
// The test target hosts the app, so @testable access works via TEST_HOST / BUNDLE_LOADER.

// MARK: - Helpers

/// Make a minimal SleepRecord with phases for a given day index.
private func makeRecord(day: Int, withPhases: Bool = true) -> SleepRecord {
    let phases: [PhaseInterval] = withPhases
        ? [PhaseInterval(hour: 0, phase: .light, timestamp: 0)]
        : []
    return SleepRecord(
        day: day, date: Date(), isWeekend: false,
        bedtimeHour: 23.0, wakeupHour: 7.0,
        sleepDuration: 8.0, phases: phases,
        hourlyActivity: [], cosinor: .empty,
        driftMinutes: 0
    )
}

private func makeWindow(effective: Int, count: Int, requested: Int? = nil, clamped: Bool = false) -> VisibleDayWindow {
    VisibleDayWindow(
        requestedActiveIndex: requested ?? effective,
        effectiveActiveIndex: effective,
        startIndex: max(0, effective - count + 1),
        endIndex: effective,
        visibleCount: count,
        clampedToDataBounds: clamped
    )
}

/// Convenience: create a SpiralRenderState via resolve() with typical defaults.
/// `cursorTurns` in test context means the active position of the user on the spiral.
/// It is passed as both spiralExtentTurns (geometry) and cursorAbsHour (active position)
/// since tests don't distinguish the two concepts.
private func resolveState(
    records: [SleepRecord],
    activeTurns: Double,
    visibleDays: Double,
    totalTurns: Double? = nil,
    cameraMaxTurn: Double? = nil,
    showAccentMarker: Bool = false,
    showDebugDot: Bool = false,
    showContextMarkers: Bool = true
) -> SpiralRenderState {
    let total = totalTurns ?? max(activeTurns, Double(records.count))
    let cam = cameraMaxTurn ?? total
    // Retrospective viewport: cursor marks the END of the window
    let vpFrom = max(activeTurns - visibleDays, 0)
    let vpUpTo = activeTurns
    let camFrom = vpFrom
    let camUpTo = activeTurns
    let backboneCap = activeTurns + 0.15
    return SpiralVisibilityEngine.resolve(
        records: records,
        cursorAbsHour: activeTurns * 24.0,
        viewportFromTurns: vpFrom,
        viewportUpToTurns: vpUpTo,
        cameraFromTurns: camFrom,
        cameraUpToTurns: camUpTo,
        spiralExtentTurns: total,
        spiralPeriod: 24.0,
        cameraMaxTurn: cam,
        backboneCapTurn: backboneCap,
        showAccentMarker: showAccentMarker,
        showDebugDot: showDebugDot,
        showContextMarkers: showContextMarkers
    )
}

// MARK: - DataDayBounds

@Suite("SpiralVisibilityEngine — DataDayBounds")
struct DataDayBoundsTests {

    @Test("Empty records → hasData = false")
    func emptyRecords() {
        let bounds = SpiralVisibilityEngine.computeDataDayBounds([])
        #expect(!bounds.hasData)
    }

    @Test("Records without phases → hasData = false")
    func recordsWithoutPhases() {
        let records = (0..<5).map { makeRecord(day: $0, withPhases: false) }
        let bounds = SpiralVisibilityEngine.computeDataDayBounds(records)
        #expect(!bounds.hasData)
    }

    @Test("Single record → firstDayIndex == lastDayIndex")
    func singleRecord() {
        let bounds = SpiralVisibilityEngine.computeDataDayBounds([makeRecord(day: 5)])
        #expect(bounds.hasData)
        #expect(bounds.firstDayIndex == 5)
        #expect(bounds.lastDayIndex == 5)
    }

    @Test("Multiple records → correct first and last")
    func multipleRecords() {
        let records = [3, 7, 1, 10, 2].map { makeRecord(day: $0) }
        let bounds = SpiralVisibilityEngine.computeDataDayBounds(records)
        #expect(bounds.firstDayIndex == 1)
        #expect(bounds.lastDayIndex == 10)
    }

    @Test("Mix of records with and without phases")
    func mixedPhases() {
        let records = [
            makeRecord(day: 0, withPhases: false),
            makeRecord(day: 5, withPhases: true),
            makeRecord(day: 10, withPhases: false),
            makeRecord(day: 12, withPhases: true),
        ]
        let bounds = SpiralVisibilityEngine.computeDataDayBounds(records)
        #expect(bounds.firstDayIndex == 5)
        #expect(bounds.lastDayIndex == 12)
    }
}

// MARK: - Effective active index (via computeVisibleDayWindow)
// computeVisibleDayCount and computeEffectiveActiveDayIndex were removed.
// The day window is now derived from viewport turns. Effective active
// follows the cursor directly (no clamping to data bounds).

// MARK: - computeVisibleDayWindow (viewport-derived)

@Suite("SpiralVisibilityEngine — computeVisibleDayWindow")
struct VisibleDayWindowTests {

    private let bounds14 = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)

    @Test("Normal viewport within data — window covers viewport days")
    func normalViewport() {
        // Viewport [4, 11] → startIndex=4, endIndex=11
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 10.5, viewportFromTurns: 4.0, viewportUpToTurns: 11.0, bounds: bounds14)
        #expect(window.requestedActiveIndex == 10)
        #expect(window.effectiveActiveIndex == 10)
        #expect(!window.clampedToDataBounds)
        #expect(window.startIndex == 4)
        #expect(window.endIndex == 11)
    }

    @Test("Cursor far ahead of data — effective follows cursor, window covers viewport")
    func cursorFarAhead() {
        // Cursor at 30, viewport [26, 34] → effective follows cursor at 30
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 30.0, viewportFromTurns: 26.0, viewportUpToTurns: 34.0, bounds: bounds14)
        #expect(window.requestedActiveIndex == 30)
        #expect(window.effectiveActiveIndex == 30)
        #expect(!window.clampedToDataBounds)
        #expect(window.startIndex == 26)
        #expect(window.endIndex == 34)
    }

    @Test("Viewport centered on data — covers latest data day")
    func windowCoversLatestDataDay() {
        // viewport [7, 14] → covers day 13
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 100.0, viewportFromTurns: 7.0, viewportUpToTurns: 14.0, bounds: bounds14)
        #expect(window.endIndex >= bounds14.lastDayIndex)
        let noFallback = !SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds14, window: window)
        #expect(noFallback, "Data exists but shouldShowNoDataFallback returned true")
    }

    @Test("Empty dataset — fallback fires")
    func emptyDataset() {
        let emptyBounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 0, hasData: false)
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 5.0, viewportFromTurns: 1.5, viewportUpToTurns: 8.5, bounds: emptyBounds)
        #expect(SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: emptyBounds, window: window))
    }

    @Test("Close zoom — viewport-derived window is narrow")
    func zoomExtreme() {
        // Viewport [9.5, 10.5] → startIndex=9, endIndex=10
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 10.0, viewportFromTurns: 9.5, viewportUpToTurns: 10.5, bounds: bounds14)
        #expect(window.startIndex == 9)
        #expect(window.endIndex == 10)
    }

    @Test("Wide viewport — all data days visible")
    func wideViewport() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 5, hasData: true)
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 50.0, viewportFromTurns: 0.0, viewportUpToTurns: 50.0, bounds: bounds)
        #expect(window.effectiveActiveIndex == 5)
        #expect(window.startIndex == 0)
        #expect(window.endIndex == 50)
        #expect(!SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds, window: window))
    }
}

// MARK: - visibilityState (viewport-derived, styling only)

@Suite("SpiralVisibilityEngine — visibilityState")
struct VisibilityStateTests {

    @Test("Active day → opacity 1.0")
    func activeDay() {
        let window = makeWindow(effective: 10, count: 7)
        let vis = SpiralVisibilityEngine.visibilityState(for: 10, window: window)
        #expect(vis.isVisible)
        #expect(vis.opacity == 1.0)
        #expect(vis.distanceFromActive == 0)
    }

    @Test("One day back → opacity 0.75")
    func oneDayBack() {
        let window = makeWindow(effective: 10, count: 7)
        let vis = SpiralVisibilityEngine.visibilityState(for: 9, window: window)
        #expect(vis.isVisible)
        #expect(vis.opacity == 0.75)
    }

    @Test("Distant day inside window → visible with opacity floor 0.05")
    func distantDayInsideWindow() {
        let window = makeWindow(effective: 10, count: 7)
        let vis = SpiralVisibilityEngine.visibilityState(for: 4, window: window)  // dist = 6
        #expect(vis.isVisible, "Days inside viewport must always be visible")
        #expect(vis.opacity >= 0.05, "Opacity floor must be at least 0.05, got \(vis.opacity)")
    }

    @Test("Day outside window → invisible")
    func outsideWindow() {
        let window = makeWindow(effective: 10, count: 7)
        let vis = SpiralVisibilityEngine.visibilityState(for: 3, window: window)  // outside [4..10]
        #expect(!vis.isVisible)
        #expect(vis.opacity == 0)
    }

    @Test("Day past endIndex → invisible")
    func pastEndIndex() {
        let window = makeWindow(effective: 10, count: 7)
        let vis = SpiralVisibilityEngine.visibilityState(for: 11, window: window)
        #expect(!vis.isVisible)
    }

    @Test("After clamping: all days inside window are visible")
    func clampedWindowAllVisible() {
        // Viewport-derived window [7…13], effective clamped to 13
        let clampedWindow = VisibleDayWindow(
            requestedActiveIndex: 30,
            effectiveActiveIndex: 13,
            startIndex: 7,
            endIndex: 13,
            visibleCount: 7,
            clampedToDataBounds: true
        )
        // Day 13 should be fully visible
        let vis13 = SpiralVisibilityEngine.visibilityState(for: 13, window: clampedWindow)
        #expect(vis13.isVisible)
        #expect(vis13.opacity == 1.0)

        // Day 7 should be visible (inside window, opacity >= 0.05)
        let vis7 = SpiralVisibilityEngine.visibilityState(for: 7, window: clampedWindow)
        #expect(vis7.isVisible)
        #expect(vis7.opacity >= 0.05)

        // Day 6 (outside window) should be invisible
        let vis6 = SpiralVisibilityEngine.visibilityState(for: 6, window: clampedWindow)
        #expect(!vis6.isVisible)
    }

    @Test("strokeScale and blur degrade with distance")
    func strokeScaleAndBlur() {
        let window = makeWindow(effective: 10, count: 7)
        let vis0 = SpiralVisibilityEngine.visibilityState(for: 10, window: window)
        let vis3 = SpiralVisibilityEngine.visibilityState(for: 7, window: window)  // dist = 3
        #expect(vis0.strokeScale == 1.0)
        #expect(vis0.blur == 0.0)
        #expect(vis3.strokeScale < vis0.strokeScale)
        #expect(vis3.blur > vis0.blur)
    }
}

// MARK: - shouldShowNoDataFallback

@Suite("SpiralVisibilityEngine — shouldShowNoDataFallback")
struct NoDataFallbackTests {

    @Test("No data → fallback true")
    func noData() {
        let empty = DataDayBounds(firstDayIndex: 0, lastDayIndex: 0, hasData: false)
        let window = VisibleDayWindow(
            requestedActiveIndex: 0, effectiveActiveIndex: 0,
            startIndex: 0, endIndex: 0, visibleCount: 7, clampedToDataBounds: false)
        #expect(SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: empty, window: window))
    }

    @Test("Data exists and window covers it → fallback false")
    func dataCoversWindow() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        let window = VisibleDayWindow(
            requestedActiveIndex: 13, effectiveActiveIndex: 13,
            startIndex: 7, endIndex: 13, visibleCount: 7, clampedToDataBounds: false)
        #expect(!SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds, window: window))
    }

    @Test("Cursor far beyond data but window clamped → fallback false (the bug case)")
    func clampedWindowNeverFallback() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        // After clamping, window is [7…13], data is [0…13] → overlap → no fallback
        let window = VisibleDayWindow(
            requestedActiveIndex: 100, effectiveActiveIndex: 13,
            startIndex: 7, endIndex: 13, visibleCount: 7, clampedToDataBounds: true)
        #expect(!SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds, window: window))
    }

    @Test("No false gray fallback when data exists with any viewport position")
    func noFalseGrayFallback() {
        let bounds = DataDayBounds(firstDayIndex: 2, lastDayIndex: 8, hasData: true)
        // Test many viewport positions that overlap data — none should trigger fallback
        for center in [2.0, 5.0, 8.0, 15.0, 50.0, 100.0] {
            let vpFrom = max(center - 5.0, 0)
            let vpUpTo = center + 5.0
            let window = SpiralVisibilityEngine.computeVisibleDayWindow(
                activeTurns: center, viewportFromTurns: vpFrom, viewportUpToTurns: vpUpTo, bounds: bounds)
            let fallback = SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds, window: window)
            #expect(!fallback, "False fallback at center=\(center)")
        }
    }
}

// MARK: - Origin Visibility (zoom-dependent)

@Suite("SpiralVisibilityEngine — Origin Visibility")
struct OriginVisibilityTests {

    @Test("Origin fully visible at close zoom (zoom ≤ zoomFullVisible)")
    func originVisibleAtCloseZoom() {
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: 1.0)
        #expect(origin.isVisible)
        #expect(origin.opacity == 1.0)
        #expect(origin.screenRadius >= OriginVisibilityState.minScreenRadius)
    }

    @Test("Origin at zoomFullVisible threshold → fully visible")
    func originAtFullVisibleThreshold() {
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: OriginVisibilityState.zoomFullVisible)
        #expect(origin.isVisible)
        #expect(origin.opacity == 1.0)
    }

    @Test("Origin at medium zoom → partially visible (0 < opacity < 1)")
    func originPartiallyVisibleAtMediumZoom() {
        let midZoom = (OriginVisibilityState.zoomFullVisible + OriginVisibilityState.zoomFullHidden) / 2.0
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: midZoom)
        #expect(origin.isVisible)
        #expect(origin.opacity > 0)
        #expect(origin.opacity < 1.0)
    }

    @Test("Origin at zoomFullHidden → hidden")
    func originHiddenAtFarZoom() {
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: OriginVisibilityState.zoomFullHidden)
        #expect(!origin.isVisible)
        #expect(origin.opacity == 0)
    }

    @Test("Origin at extreme zoom out → hidden")
    func originHiddenAtExtremeZoomOut() {
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: 100.0)
        #expect(!origin.isVisible)
        #expect(origin.opacity == 0)
        #expect(origin.screenRadius == 0)
    }

    @Test("Origin hidden when no data at any zoom")
    func originHiddenWithoutData() {
        for zoom in [0.5, 1.0, 3.0, 5.0, 100.0] {
            let origin = SpiralVisibilityEngine.computeOriginVisibility(
                hasData: false, zoom: zoom)
            #expect(!origin.isVisible, "Origin should be hidden with no data at zoom=\(zoom)")
            #expect(origin.opacity == 0)
        }
    }

    @Test("Origin visible at extreme zoom in — not culled by day visibility window")
    func originVisibleAtExtremeZoomIn() {
        // Active day is 20, window shows days 18-20, but origin uses zoom only.
        let window = makeWindow(effective: 20, count: 3)
        // Day 0 is outside day visibility:
        let dayVis = SpiralVisibilityEngine.visibilityState(for: 0, window: window)
        #expect(!dayVis.isVisible, "Day 0 should be outside the day visibility window")
        // But origin at close zoom is visible (independent of window):
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: 0.5)
        #expect(origin.isVisible, "Origin must be visible at close zoom regardless of day window")
        #expect(origin.opacity == 1.0)
    }

    @Test("Origin opacity decreases monotonically as zoom increases")
    func originOpacityMonotonicWithZoom() {
        var prevOpacity = 2.0  // start above max
        for zoom in stride(from: 0.5, through: 15.0, by: 0.5) {
            let origin = SpiralVisibilityEngine.computeOriginVisibility(
                hasData: true, zoom: zoom)
            #expect(origin.opacity <= prevOpacity,
                    "Origin opacity should decrease with zoom: at zoom=\(zoom) got \(origin.opacity) > prev \(prevOpacity)")
            prevOpacity = origin.opacity
        }
    }

    @Test("Origin screen radius ≥ minimum when visible")
    func originRadiusNeverBelowMinimumWhenVisible() {
        for zoom in [0.1, 0.5, 1.0, 3.0, 5.0, 8.0] {
            let origin = SpiralVisibilityEngine.computeOriginVisibility(
                hasData: true, zoom: zoom)
            if origin.isVisible {
                #expect(origin.screenRadius >= OriginVisibilityState.minScreenRadius,
                        "Origin radius too small at zoom=\(zoom)")
            }
        }
    }

    @Test("Origin hidden at far zoom does NOT mean no data — spiral still visible")
    func originHiddenDoesNotImplyNoData() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        let zoom = 50.0  // far beyond zoomFullHidden

        // Origin is hidden
        let origin = SpiralVisibilityEngine.computeOriginVisibility(
            hasData: true, zoom: zoom)
        #expect(!origin.isVisible)

        // But data is still renderable (no fallback)
        let window = SpiralVisibilityEngine.computeVisibleDayWindow(
            activeTurns: 7.0, viewportFromTurns: 0.0, viewportUpToTurns: zoom, bounds: bounds)
        #expect(!SpiralVisibilityEngine.shouldShowNoDataFallback(bounds: bounds, window: window))

        // And at least one data day is visible
        let anyVisible = (bounds.firstDayIndex...bounds.lastDayIndex).contains { dayIdx in
            SpiralVisibilityEngine.visibilityState(for: dayIdx, window: window).isVisible
        }
        #expect(anyVisible, "Data days must be visible even when origin is hidden by zoom")
    }
}

// MARK: - computeRenderTurnRange (viewport-based)

@Suite("SpiralVisibilityEngine — computeRenderTurnRange")
struct RenderTurnRangeTests {

    @Test("Normal case: render range covers camera window")
    func normalRange() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 4.0, cameraUpTo: 11.0, viewportFrom: 4.0, bounds: bounds,
            backboneCapTurn: 11.15, cameraMaxTurn: 20.0)
        #expect(result.from <= 4.0)
        #expect(result.upTo >= 11.0)
    }

    @Test("Render range extends to camera upTo + margin")
    func backboneExtension() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 7.0, cameraUpTo: 14.0, viewportFrom: 7.0, bounds: bounds,
            backboneCapTurn: 14.15, cameraMaxTurn: 20.0)
        #expect(result.upTo >= 14.0,
                "Render range should cover camera upTo")
    }

    @Test("Wide camera → render range covers full range")
    func wideViewport() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 0.0, cameraUpTo: 100.0, viewportFrom: 0.0, bounds: bounds,
            backboneCapTurn: 100.15, cameraMaxTurn: 50.0)
        #expect(result.from == 0.0)
        #expect(result.upTo >= 50.0)
    }

    @Test("Narrow camera → render range matches camera + margin")
    func narrowViewport() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 5, hasData: true)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 2.0, cameraUpTo: 4.0, viewportFrom: 2.0, bounds: bounds,
            backboneCapTurn: 4.15, cameraMaxTurn: 3.0)
        #expect(result.from <= 2.0)
        #expect(result.upTo >= 3.0)
    }

    @Test("Empty dataset → range governed by camera + backbone")
    func emptyDataset() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 0, hasData: false)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 0.0, cameraUpTo: 6.0, viewportFrom: 0.0, bounds: bounds,
            backboneCapTurn: 6.15, cameraMaxTurn: 3.0)
        #expect(result.from == 0.0)
        #expect(result.upTo >= 3.0)
    }

    @Test("Non-degenerate range safety — upTo always > from")
    func nonDegenerateRange() {
        let bounds = DataDayBounds(firstDayIndex: 5, lastDayIndex: 5, hasData: true)
        let result = SpiralVisibilityEngine.computeRenderTurnRange(
            cameraFrom: 3.0, cameraUpTo: 6.0, viewportFrom: 3.0, bounds: bounds,
            backboneCapTurn: 6.15, cameraMaxTurn: 0.1)
        #expect(result.upTo > result.from,
                Comment(rawValue: "Render range must be non-degenerate: from=\(result.from) upTo=\(result.upTo)"))
    }
}

// MARK: - Marker Rendering

@Suite("Marker Rendering State")
struct MarkerRenderingTests {

    @Test("Default markers via resolve: no accent, no debug dot, context markers on")
    func defaultMarkers() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0)
        #expect(!state.markerState.shouldRenderOriginAccent)
        #expect(!state.markerState.shouldRenderOriginDebugDot)
        #expect(state.markerState.shouldRenderContextMarkers)
    }

    @Test("Explicit accent opt-in enables accent")
    func accentOptIn() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0,
                                 showAccentMarker: true)
        #expect(state.markerState.shouldRenderOriginAccent)
        #expect(!state.markerState.shouldRenderOriginDebugDot)
    }

    @Test("Explicit debug dot opt-in enables debug dot")
    func debugDotOptIn() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0,
                                 showDebugDot: true)
        #expect(!state.markerState.shouldRenderOriginAccent)
        #expect(state.markerState.shouldRenderOriginDebugDot)
    }

    @Test("Both accent and debug dot can be enabled simultaneously")
    func bothEnabled() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0,
                                 showAccentMarker: true, showDebugDot: true)
        #expect(state.markerState.shouldRenderOriginAccent)
        #expect(state.markerState.shouldRenderOriginDebugDot)
    }

    @Test("Origin green dot does NOT render by default — regression guard")
    func originGreenDotNotRenderedByDefault() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0)
        #expect(!state.markerState.shouldRenderOriginAccent)
    }

    @Test("Marker state is orthogonal to origin visibility — accent off doesn't hide origin")
    func markerStateOrthogonalToOriginVisibility() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 2.0)
        // Origin structural anchor is visible (zoom 2.0 < zoomFullVisible 3.0)
        #expect(state.originState.isVisible)
        #expect(state.originState.opacity == 1.0)
        // But accent marker is NOT rendered
        #expect(!state.markerState.shouldRenderOriginAccent)
    }

    @Test("Context markers default to true")
    func contextMarkersDefaultTrue() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0)
        #expect(state.markerState.shouldRenderContextMarkers)
    }

    @Test("Context markers can be disabled")
    func contextMarkersDisabled() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0,
                                 showContextMarkers: false)
        #expect(!state.markerState.shouldRenderContextMarkers)
    }
}

// MARK: - resolve() Integration

@Suite("SpiralVisibilityEngine — resolve() Integration")
struct ResolveIntegrationTests {

    @Test("resolve returns non-nil state with all subsystems populated")
    func resolveReturnsCompleteState() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 13.0, visibleDays: 7.0)
        #expect(state.dataBounds.hasData)
        #expect(state.dataBounds.firstDayIndex == 0)
        #expect(state.dataBounds.lastDayIndex == 13)
        #expect(state.visibleWindow.visibleCount == 7)
        #expect(state.renderUpToTurns > state.renderFromTurns)
        #expect(!state.showNoDataFallback)
    }

    @Test("resolve with empty records → fallback state")
    func resolveEmptyRecords() {
        let state = resolveState(records: [], activeTurns: 5.0, visibleDays: 7.0, totalTurns: 10.0)
        #expect(!state.dataBounds.hasData)
        #expect(state.showNoDataFallback)
        #expect(!state.originState.isVisible)
    }

    @Test("dayVisibility(for:) on SpiralRenderState matches engine directly")
    func dayVisibilityDelegation() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 10.0, visibleDays: 7.0)
        for day in 0...13 {
            let fromState = state.dayVisibility(for: day)
            let direct = SpiralVisibilityEngine.visibilityState(for: day, window: state.visibleWindow)
            #expect(fromState.isVisible == direct.isVisible)
            #expect(fromState.opacity == direct.opacity)
        }
    }

    @Test("contextVisibility(for:) follows day visibility + context marker flag")
    func contextVisibilityFollowsDayVis() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 10.0, visibleDays: 7.0)
        for day in 0...13 {
            let ctx = state.contextVisibility(for: day)
            let dayVis = state.dayVisibility(for: day)
            if dayVis.isVisible && state.markerState.shouldRenderContextMarkers {
                #expect(ctx.isVisible, "Context should be visible for visible day \(day)")
                #expect(ctx.opacity == dayVis.opacity)
            } else {
                #expect(!ctx.isVisible, "Context should be hidden for invisible day \(day)")
            }
        }
    }

    @Test("contextVisibility hidden when context markers disabled")
    func contextVisibilityHiddenWhenDisabled() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 10.0, visibleDays: 7.0,
                                 showContextMarkers: false)
        // Even though days are visible, context should be hidden
        let ctx = state.contextVisibility(for: 10)
        #expect(!ctx.isVisible)
    }

    @Test("Dataset cursor=0 at start → all five systems consistent")
    func cursorAtStart() {
        let records = (0..<6).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 1.0)
        // Day 0 visible
        #expect(state.dayVisibility(for: 0).isVisible)
        // Origin visible (zoom 1.0 < zoomFullVisible 3.0)
        #expect(state.originState.isVisible)
        // No fallback
        #expect(!state.showNoDataFallback)
        // No accent
        #expect(!state.markerState.shouldRenderOriginAccent)
        // Context follows day visibility
        #expect(state.contextVisibility(for: 0).isVisible)
    }

    @Test("Full pipeline: data exists → cannot have invisible spiral + gray fallback")
    func fullPipelineNoFalseGray() {
        let records = (0..<14).map { makeRecord(day: $0) }

        // Test many cursor+zoom combos
        let cursors = [0.0, 5.0, 13.0, 14.0, 20.0, 50.0, 100.0]
        let zooms   = [0.15, 1.0, 2.0, 5.0, 7.0, 13.0, 50.0, 100.0]
        for cursor in cursors {
            for zoom in zooms {
                let state = resolveState(records: records, activeTurns: cursor, visibleDays: zoom)
                #expect(!state.showNoDataFallback,
                        "False fallback at cursor=\(cursor) zoom=\(zoom)")

                // At least one data day must be visible
                let anyVisible = (0...13).contains { dayIdx in
                    state.dayVisibility(for: dayIdx).isVisible
                }
                #expect(anyVisible,
                        "No visible data day at cursor=\(cursor) zoom=\(zoom)")
            }
        }
    }

    @Test("Full pipeline: 5 systems independent — all consistent at close zoom")
    func fiveSystemsIndependentCloseZoom() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 7.0, visibleDays: 2.0)
        // System 1: day visibility — day 7 should be visible
        #expect(state.dayVisibility(for: 7).isVisible)
        // System 2: origin — visible at close zoom (2.0 < zoomFullVisible 3.0)
        #expect(state.originState.isVisible)
        #expect(state.originState.opacity == 1.0)
        // System 3: no-data fallback — must be false
        #expect(!state.showNoDataFallback)
        // System 4: marker rendering — no accent by default
        #expect(!state.markerState.shouldRenderOriginAccent)
        #expect(!state.markerState.shouldRenderOriginDebugDot)
        // System 5: context visibility — follows day vis
        #expect(state.contextVisibility(for: 7).isVisible)
    }

    @Test("Full pipeline: 5 systems independent — origin hidden at far zoom, data still visible")
    func fiveSystemsIndependentFarZoom() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 7.0, visibleDays: 50.0)
        // System 1: day visibility — day 7 should be visible
        #expect(state.dayVisibility(for: 7).isVisible)
        // System 2: origin — hidden at far zoom (50 >= zoomFullHidden 10)
        #expect(!state.originState.isVisible)
        // System 3: no-data fallback — must be false (data exists!)
        #expect(!state.showNoDataFallback)
        // System 4: marker rendering — no accent by default
        #expect(!state.markerState.shouldRenderOriginAccent)
        // System 5: context visibility — still follows day vis
        #expect(state.contextVisibility(for: 7).isVisible)
    }

    @Test("Zoom max + cursor extreme → visible window clamp correct, no false fallback")
    func zoomMaxCursorExtreme() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 500.0, visibleDays: 500.0)
        // Window must be clamped
        #expect(state.effectiveActiveIndex == 13)
        // No fallback
        #expect(!state.showNoDataFallback)
        // Data day 13 must be visible
        #expect(state.dayVisibility(for: 13).isVisible)
        #expect(state.dayVisibility(for: 13).opacity == 1.0)
    }

    @Test("Zoom min + origin → origin stays visible")
    func zoomMinOriginVisible() {
        let records = [makeRecord(day: 0)]
        let state = resolveState(records: records, activeTurns: 0.0, visibleDays: 0.15)
        #expect(state.originState.isVisible)
        #expect(state.originState.opacity == 1.0)
    }
}

// MARK: - Dead Zone / Zoom Continuity Tests

@Suite("SpiralVisibilityEngine — No Dead Zones")
struct NoDeadZoneTests {

    /// THE CRITICAL TEST: sweep zoom from min to max — spiral must never vanish
    /// if data exists. This is the exact scenario that caused Bug 4.
    @Test("Zoom sweep: no zoom level where data-bearing spiral disappears")
    func zoomSweepNoDisappearance() {
        let records = (0..<14).map { makeRecord(day: $0) }
        var zooms: [Double] = []
        // Fine-grained sweep through the entire zoom range
        var z = 0.15
        while z <= 200.0 {
            zooms.append(z)
            z += 0.25
        }
        zooms.append(200.0)

        for zoom in zooms {
            let state = resolveState(
                records: records, activeTurns: 13.5, visibleDays: zoom,
                totalTurns: 14.0, cameraMaxTurn: max(zoom, 14.0))
            // Fallback must be false
            #expect(!state.showNoDataFallback,
                    "False fallback (dead zone) at zoom=\(zoom)")
            // At least one data day visible
            let anyVisible = (0...13).contains {
                state.dayVisibility(for: $0).isVisible
            }
            #expect(anyVisible,
                    "No visible data day (dead zone) at zoom=\(zoom)")
        }
    }

    /// Sweep zoom: render range must always cover at least the data extent.
    @Test("Zoom sweep: render range always covers data")
    func zoomSweepRenderRangeCoversData() {
        let records = (0..<14).map { makeRecord(day: $0) }
        var z = 0.15
        while z <= 200.0 {
            let state = resolveState(
                records: records, activeTurns: 13.5, visibleDays: z,
                totalTurns: 14.0, cameraMaxTurn: max(z, 14.0))
            #expect(state.renderUpToTurns >= 14.0,
                    "Render range doesn't cover data at zoom=\(z): upTo=\(state.renderUpToTurns)")
            z += 0.5
        }
    }

    /// Sweep zoom with extreme cursor offset (cursor far past data).
    @Test("Zoom sweep with cursor far past data: no dead zones")
    func zoomSweepCursorFarPast() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let cursors: [Double] = [14.0, 20.0, 50.0, 100.0, 500.0]
        let zooms: [Double] = [0.15, 1.0, 3.0, 5.0, 10.0, 20.0, 50.0, 100.0, 500.0]

        for cursor in cursors {
            for zoom in zooms {
                let state = resolveState(
                    records: records, activeTurns: cursor, visibleDays: zoom,
                    totalTurns: cursor, cameraMaxTurn: max(cursor, 50.0))
                #expect(!state.showNoDataFallback,
                        "False fallback at cursor=\(cursor) zoom=\(zoom)")
                let anyVisible = (0...13).contains {
                    state.dayVisibility(for: $0).isVisible
                }
                #expect(anyVisible,
                        "No visible data day at cursor=\(cursor) zoom=\(zoom)")
            }
        }
    }

    /// Camera horizon below data: data must still be renderable.
    @Test("Camera clips below data range → data still renderable")
    func cameraClipsBelowDataRange() {
        let records = (0..<14).map { makeRecord(day: $0) }
        // Camera can only see up to turn 5 — but data goes to turn 13
        let state = resolveState(
            records: records, activeTurns: 13.5, visibleDays: 7.0,
            totalTurns: 14.0, cameraMaxTurn: 5.0)
        #expect(state.renderUpToTurns >= 14.0,
                "Render range must extend beyond camera to cover data")
        #expect(!state.showNoDataFallback)
    }
}

// MARK: - Context Band Coherence Tests

@Suite("SpiralVisibilityEngine — Context Band Coherence")
struct ContextBandCoherenceTests {

    /// If a day is visible, its context block must also be visible (when context markers enabled).
    @Test("Context visibility is coherent with day visibility")
    func contextCoherentWithDayVisibility() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let zooms: [Double] = [0.15, 1.0, 2.0, 5.0, 7.0, 13.0, 50.0, 100.0]
        for zoom in zooms {
            let state = resolveState(records: records, activeTurns: 10.0, visibleDays: zoom)
            for day in 0...13 {
                let dayVis = state.dayVisibility(for: day)
                let ctxVis = state.contextVisibility(for: day)
                if dayVis.isVisible {
                    #expect(ctxVis.isVisible,
                            "Day \(day) visible but context hidden at zoom=\(zoom)")
                    #expect(ctxVis.opacity == dayVis.opacity,
                            "Context opacity \(ctxVis.opacity) != day opacity \(dayVis.opacity) at zoom=\(zoom)")
                }
            }
        }
    }

    /// Zoom sweep: if any data day is rendered, its context band opacity must match.
    @Test("Zoom sweep: context opacity matches day opacity everywhere")
    func zoomSweepContextOpacityMatchesDayOpacity() {
        let records = (0..<14).map { makeRecord(day: $0) }
        var z = 0.15
        while z <= 100.0 {
            let state = resolveState(records: records, activeTurns: 13.0, visibleDays: z)
            for day in 0...13 {
                let dayVis = state.dayVisibility(for: day)
                let ctxVis = state.contextVisibility(for: day)
                if dayVis.isVisible {
                    #expect(ctxVis.opacity == dayVis.opacity,
                            "Mismatch at day=\(day) zoom=\(z): ctx=\(ctxVis.opacity) day=\(dayVis.opacity)")
                }
            }
            z += 1.0
        }
    }

    /// No "blue bands missing" scenario: at every zoom level where data is visible,
    /// context for those days is also visible.
    @Test("No missing blue bands when spiral data is visible")
    func noMissingBlueBands() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let cursors: [Double] = [5.0, 13.0, 30.0, 100.0]
        let zooms: [Double] = [0.15, 1.0, 3.0, 7.0, 15.0, 50.0]

        for cursor in cursors {
            for zoom in zooms {
                let state = resolveState(
                    records: records, activeTurns: cursor, visibleDays: zoom,
                    totalTurns: max(cursor, 14.0), cameraMaxTurn: max(cursor, 50.0))
                let visibleDays = (0...13).filter {
                    state.dayVisibility(for: $0).isVisible
                }
                let contextVisibleDays = (0...13).filter {
                    state.contextVisibility(for: $0).isVisible
                }
                #expect(Set(visibleDays) == Set(contextVisibleDays),
                        "Visible days \(visibleDays) != context days \(contextVisibleDays) at cursor=\(cursor) zoom=\(zoom)")
            }
        }
    }
}

// MARK: - Zoom Continuity Tests

@Suite("SpiralVisibilityEngine — Zoom Continuity")
struct ZoomContinuityTests {

    /// The visible day count (viewport-derived) is non-decreasing as viewport widens.
    @Test("Visible day count is monotonically non-decreasing with viewport width")
    func visibleDayCountMonotonic() {
        let bounds = DataDayBounds(firstDayIndex: 0, lastDayIndex: 13, hasData: true)
        var prevCount = 0
        for span in stride(from: 0.5, through: 20.0, by: 0.5) {
            let window = SpiralVisibilityEngine.computeVisibleDayWindow(
                activeTurns: 7.0, viewportFromTurns: max(7.0 - span / 2, 0),
                viewportUpToTurns: 7.0 + span / 2, bounds: bounds)
            #expect(window.visibleCount >= prevCount,
                    "Visible day count decreased from \(prevCount) to \(window.visibleCount) at span=\(span)")
            prevCount = window.visibleCount
        }
    }

    /// Render range should vary smoothly (no large discontinuities).
    @Test("Render range changes smoothly across zoom levels")
    func renderRangeSmoothAcrossZoom() {
        let records = (0..<14).map { makeRecord(day: $0) }
        var prevUpTo: Double = 0
        var z = 0.15
        while z <= 100.0 {
            let state = resolveState(
                records: records, activeTurns: 13.5, visibleDays: z,
                totalTurns: 14.0, cameraMaxTurn: 100.0)
            // Allow jumps up to 3 turns (day count transitions from 3→5→7)
            if prevUpTo > 0 {
                let jump = abs(state.renderUpToTurns - prevUpTo)
                #expect(jump < 5.0,
                        "Large render range discontinuity at zoom=\(z): prev=\(prevUpTo) now=\(state.renderUpToTurns)")
            }
            prevUpTo = state.renderUpToTurns
            z += 0.25
        }
    }

    /// Effective active index should not oscillate as zoom changes.
    @Test("Effective active index is stable across zoom sweep")
    func effectiveActiveIndexStable() {
        let records = (0..<14).map { makeRecord(day: $0) }
        // With cursor at 13.5, effective should be 13 at all zoom levels (since data exists)
        var z = 0.15
        while z <= 200.0 {
            let state = resolveState(
                records: records, activeTurns: 13.5, visibleDays: z,
                totalTurns: 14.0, cameraMaxTurn: 200.0)
            #expect(state.effectiveActiveIndex == 13,
                    "Effective active index changed to \(state.effectiveActiveIndex) at zoom=\(z)")
            z += 0.5
        }
    }

    /// With cursor far past data, effective active should stay at lastDayIndex.
    @Test("Cursor far past data: effective active follows cursor across all zooms")
    func effectiveActiveFollowsCursorPastData() {
        let records = (0..<14).map { makeRecord(day: $0) }
        for zoom in [0.15, 1.0, 5.0, 10.0, 50.0, 200.0] {
            let state = resolveState(
                records: records, activeTurns: 500.0, visibleDays: zoom,
                totalTurns: 500.0, cameraMaxTurn: 500.0)
            // effectiveActive follows cursor directly (no clamping to data bounds)
            #expect(state.effectiveActiveIndex == 500,
                    "At zoom=\(zoom), effective should be 500 but got \(state.effectiveActiveIndex)")
        }
    }
}

// MARK: - Diagnostics

@Suite("SpiralVisibilityEngine — Diagnostics")
struct DiagnosticsTests {

    @Test("diagnostics() returns non-empty multi-line string")
    func diagnosticsNotEmpty() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let state = resolveState(records: records, activeTurns: 10.0, visibleDays: 7.0)
        let diag = SpiralVisibilityEngine.diagnostics(state)
        #expect(!diag.isEmpty)
        #expect(diag.contains("[SpiralVis]"))
        #expect(diag.contains("data="))
        #expect(diag.contains("window="))
        #expect(diag.contains("render="))
        #expect(diag.contains("origin="))
        #expect(diag.contains("visibleDataDays="))
    }
}
