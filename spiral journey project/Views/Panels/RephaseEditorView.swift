import SwiftUI
import SpiralKit

/// Full-screen rephase editor — shown as a sheet when the user taps the rephasePill.
/// Shows the real spiral (same as Home) with interactive target-marker drag,
/// plus wake-time picker, duration stepper, intensity selector, and optional manual bedtime toggle.
struct RephaseEditorView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    // Local copy of the plan; committed to store on Save.
    @State private var plan: RephasePlan

    // Spiral interaction state — mirrors SpiralTab
    @State private var visibleDays: Double
    @State private var liveVisibleDays: Double
    private let minVisibleDays: Double = 1

    // Drag-to-set-hour state
    @State private var isDraggingWake = false
    @State private var spiralCanvasSize: CGSize = .zero

    init(plan: RephasePlan) {
        _plan = State(initialValue: plan)
        // Start zoomed to show recent data (same init as SpiralTab)
        let turns = Double(max(30, 7))
        _visibleDays = State(initialValue: turns)
        _liveVisibleDays = State(initialValue: turns)
    }

    private var maxTurns: Double {
        let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
        return max(1.0, lastEnd / store.period)
    }

    // Match SpiralTab's effective params for log/arch consistency
    private var isLog3D: Bool {
        store.spiralType == .logarithmic && !store.flatMode
    }

    private var effectiveStartRadius: Double {
        isLog3D ? 60.0 : 75.0
    }

    private var effectiveDepthScale: Double {
        let ds = store.depthScale
        guard isLog3D else { return ds }
        return max(ds, 0.5)
    }

    private var effectivePerspectivePower: Double {
        isLog3D ? 0.5 : 1.0
    }

    private var effectiveSpiralExtent: Double {
        if store.spiralType == .logarithmic {
            let dataDays = Double(store.records.count)
            return max(min(maxTurns, dataDays + 1), 7)
        }
        return maxTurns
    }

    private var effectiveLinkGrowthToTau: Bool {
        if store.spiralType == .logarithmic && store.linkGrowthToTau {
            let tauRate = log(max(store.period, 23) / 24) / (2 * .pi)
            if abs(tauRate) < 0.001 { return false }
        }
        return store.linkGrowthToTau
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // ── Interactive spiral ──────────────────────────────
                        spiralSection

                        // ── Wake time picker ────────────────────────────────
                        sectionCard(title: String(localized: "rephase.section.wakeTarget", bundle: bundle)) {
                            wakeTimePicker
                        }

                        // ── Sleep duration ──────────────────────────────────
                        sectionCard(title: String(localized: "rephase.section.duration", bundle: bundle)) {
                            durationStepper
                        }

                        // ── Bedtime row ─────────────────────────────────────
                        sectionCard(title: String(localized: "rephase.section.bedtime", bundle: bundle)) {
                            bedtimeRow
                        }

                        // ── Intensity ───────────────────────────────────────
                        sectionCard(title: String(localized: "rephase.section.intensity", bundle: bundle)) {
                            intensitySelector
                        }

                        // ── ETA ─────────────────────────────────────────────
                        etaRow

                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle(String(localized: "rephase.title", bundle: bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "rephase.cancel", bundle: bundle)) { dismiss() }
                        .foregroundStyle(SpiralColors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "rephase.save", bundle: bundle)) { commitAndDismiss() }
                        .foregroundStyle(SpiralColors.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(store.appearance.colorScheme)
        .onAppear {
            let turns = maxTurns
            visibleDays = turns
            liveVisibleDays = turns
        }
    }

    // MARK: - Spiral section

    private var spiralSection: some View {
        let turns = maxTurns
        let maxDays = max(store.numDays, 1)

        return ZStack(alignment: .bottom) {
            GeometryReader { geo in
                SpiralView(
                    records: store.records,
                    events: store.events,
                    spiralType: store.spiralType,
                    period: store.period,
                    linkGrowthToTau: effectiveLinkGrowthToTau,
                    showCosinor: false,
                    showBiomarkers: false,
                    showTwoProcess: false,
                    selectedDay: nil,
                    onSelectDay: { _ in },
                    contextBlocks: store.contextBlocksEnabled ? store.contextBlocks : [],
                    numDaysHint: maxDays,
                    spiralExtentTurns: effectiveSpiralExtent,
                    visibleSpanTurns: liveVisibleDays,
                    depthScale: store.flatMode ? 0 : effectiveDepthScale,
                    perspectivePower: effectivePerspectivePower,
                    targetWakeHour: plan.targetWakeHour,
                    targetBedHour: plan.derivedTargetBedHour,
                    startRadius: effectiveStartRadius
                )
                // Drag to set wake hour (same angle-finding logic as SpiralTab)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newHour = nearestHourOnSpiral(
                                at: value.location,
                                size: geo.size,
                                turns: turns,
                                maxDays: maxDays
                            )
                            isDraggingWake = true
                            withAnimation(.easeOut(duration: 0.1)) {
                                plan.targetWakeHour = newHour.truncatingRemainder(dividingBy: 24)
                            }
                        }
                        .onEnded { _ in isDraggingWake = false }
                )
                // Pinch to zoom
                .simultaneousGesture(
                    MagnifyGesture(minimumScaleDelta: 0.03)
                        .onChanged { value in
                            liveVisibleDays = max(minVisibleDays, min(turns, visibleDays / Double(value.magnification)))
                        }
                        .onEnded { value in
                            visibleDays = max(minVisibleDays, min(turns, visibleDays / Double(value.magnification)))
                            liveVisibleDays = visibleDays
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        visibleDays = turns; liveVisibleDays = turns
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onAppear { spiralCanvasSize = geo.size }
                .onChange(of: geo.size) { spiralCanvasSize = $1 }
            }
            .frame(height: 280)

            // Legend overlay at bottom of spiral
            HStack(spacing: 16) {
                legendLine(color: SpiralColors.awakeSleep,
                           label: String(format: String(localized: "rephase.spiral.wake", bundle: bundle), RephaseCalculator.formattedTargetWake(plan)))
                legendLine(color: Color(hex: "7c3aed"),
                           label: String(format: String(localized: "rephase.spiral.sleep", bundle: bundle), RephaseCalculator.formattedTargetBed(plan)))
            }
            .padding(.bottom, 10)

            // Drag hint
            if !isDraggingWake {
                Text(String(localized: "rephase.spiral.dragHint", bundle: bundle))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                    .padding(.bottom, 36)
            }
        }
        .frame(height: 280)
    }

    private func legendLine(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 18, height: 2)
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Wake time picker

    private var wakeTimePicker: some View {
        VStack(spacing: 8) {
            Text(RephaseCalculator.formatHour(plan.targetWakeHour))
                .font(.largeTitle.weight(.ultraLight).monospaced())
                .foregroundStyle(SpiralColors.awakeSleep)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hourSlots(from: 4, to: 12, step: 0.5), id: \.self) { h in
                        let isSelected = abs(plan.targetWakeHour - h) < 0.01
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                plan.targetWakeHour = h
                            }
                        } label: {
                            Text(RephaseCalculator.formatHour(h))
                                .font(.footnote.monospaced())
                                .foregroundStyle(isSelected ? SpiralColors.bg : SpiralColors.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? SpiralColors.awakeSleep : SpiralColors.surface)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Duration stepper

    private var durationStepper: some View {
        HStack {
            Text(String(format: String(localized: "rephase.duration.hours", bundle: bundle), plan.targetSleepDuration))
                .font(.headline.weight(.medium).monospaced())
                .foregroundStyle(SpiralColors.text)
            Spacer()
            Stepper("", value: Binding(
                get: { plan.targetSleepDuration },
                set: { plan.targetSleepDuration = ($0 * 2).rounded() / 2 }
            ), in: 5...10, step: 0.5)
            .labelsHidden()
            .tint(SpiralColors.accent)
        }
    }

    // MARK: - Bedtime row

    private var bedtimeRow: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RephaseCalculator.formattedTargetBed(plan))
                        .font(.title.weight(.ultraLight).monospaced())
                        .foregroundStyle(Color(hex: "a78bfa"))
                    Text(plan.manualBedtimeEnabled
                         ? String(localized: "rephase.bedtime.manual", bundle: bundle)
                         : String(localized: "rephase.bedtime.auto",   bundle: bundle))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { plan.manualBedtimeEnabled },
                    set: { plan.manualBedtimeEnabled = $0 }
                ))
                .labelsHidden()
                .tint(SpiralColors.accentDim)
            }

            if plan.manualBedtimeEnabled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hourSlots(from: 20, to: 3, step: 0.5), id: \.self) { h in
                            let isSelected = abs(plan.manualTargetBedHour - h) < 0.01
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    plan.manualTargetBedHour = h
                                }
                            } label: {
                                Text(RephaseCalculator.formatHour(h))
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(isSelected ? SpiralColors.bg : SpiralColors.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? Color(hex: "7c3aed") : SpiralColors.surface)
                                    )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Intensity selector

    private var intensitySelector: some View {
        HStack(spacing: 8) {
            ForEach(RephaseIntensity.allCases, id: \.self) { i in
                let isSelected = plan.intensity == i
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { plan.intensity = i }
                } label: {
                    VStack(spacing: 3) {
                        Text(i.displayName(bundle: bundle))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? SpiralColors.bg : SpiralColors.text)
                        Text(i.intensityDescription(bundle: bundle))
                            .font(.caption)
                            .foregroundStyle(isSelected ? SpiralColors.bg.opacity(0.7) : SpiralColors.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? SpiralColors.accent : SpiralColors.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ETA row

    @ViewBuilder
    private var etaRow: some View {
        let meanAcrophase = store.analysis.stats.meanAcrophase
        if meanAcrophase > 0 {
            let nights = RephaseCalculator.estimatedNightsToGoal(plan: plan, meanAcrophase: meanAcrophase)
            HStack(spacing: 10) {
                Image(systemName: nights == nil ? "checkmark.circle" : "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(nights == nil ? SpiralColors.good : SpiralColors.accentDim)
                Text(nights.map { n in
                    String(format: String(localized: "rephase.eta.goal", bundle: bundle), n, n == 1 ? "" : "s")
                } ?? String(localized: "rephase.eta.achieved", bundle: bundle))
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SpiralColors.surface.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8))
            )
        }
    }

    // MARK: - Layout helpers

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.muted)
                .textCase(.uppercase)
            content()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(SpiralColors.surface.opacity(0.35))
                RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8)
            }
        )
    }

    /// Generates hour values from `startH` to `endH` (wrapping midnight if needed) in `step` increments.
    private func hourSlots(from startH: Double, to endH: Double, step: Double) -> [Double] {
        var slots: [Double] = []
        var h = startH
        for _ in 0..<50 {
            let wrapped = h.truncatingRemainder(dividingBy: 24)
            slots.append(wrapped < 0 ? wrapped + 24 : wrapped)
            h += step
            let nextWrapped = h.truncatingRemainder(dividingBy: 24)
            if abs(nextWrapped - endH) < 0.01 { break }
            if h >= startH + 24 { break }
        }
        let endWrapped = endH.truncatingRemainder(dividingBy: 24)
        if !slots.contains(where: { abs($0 - endWrapped) < 0.01 }) {
            slots.append(endWrapped < 0 ? endWrapped + 24 : endWrapped)
        }
        return slots
    }

    // MARK: - Drag-to-set: nearest angular hour

    /// Given a screen point in the spiral canvas, returns the nearest clock hour (0-24)
    /// on the outermost spiral turn — used to set the target wake hour by dragging.
    private func nearestHourOnSpiral(at location: CGPoint, size: CGSize, turns: Double, maxDays: Int) -> Double {
        // Compute the center of the spiral canvas.
        // SpiralGeometry uses (width/2, height/2) as center.
        let cx = size.width / 2
        let cy = size.height / 2
        let dx = Double(location.x) - cx
        let dy = Double(location.y) - cy
        // Convert cartesian offset to angle, then to clock hour.
        // angle = 0 → 12 o'clock (top). We use atan2 with y-flipped for screen coords.
        var angle = atan2(dy, dx) + Double.pi / 2   // rotate so top = 0
        if angle < 0 { angle += 2 * Double.pi }
        let hour = (angle / (2 * Double.pi)) * store.period
        // Snap to nearest 30-minute slot
        return (hour * 2).rounded() / 2
    }

    // MARK: - Commit

    private func commitAndDismiss() {
        var updated = plan
        updated.isEnabled = true
        store.rephasePlan = updated
        dismiss()
    }
}
