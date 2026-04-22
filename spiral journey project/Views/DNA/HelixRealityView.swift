import SwiftUI
import RealityKit
import SpiralKit

/// Interactive 3D double-helix view of a SleepDNA profile using RealityKit.
///
/// Supports drag-to-rotate, pinch-to-zoom, tap-to-select-week, and motif pattern toggling.
@available(iOS 18.0, *)
struct HelixRealityView: View {

    let profile: SleepDNAProfile
    var records: [SleepRecord] = []
    @Binding var isInteractingWith3D: Bool
    /// True when the hosting mode is visible in the pager. When false,
    /// the CADisplayLink is stopped — prevents a 60fps render loop
    /// behind an invisible TabView(.page) child.
    var isActive: Bool = true

    @Environment(\.languageBundle) private var bundle
    @Environment(\.scenePhase) private var scenePhase
    @State private var manager = HelixInteractionManager()
    @State private var comparisonMode: HelixComparisonMode = .yesterday

    // ── Dirty-tracking: skip expensive ops when only transform changed ──
    private final class DirtyState {
        var selectedWeek: Int? = nil
        var selectedSlot: Int? = nil
        var showPatterns: Bool = false
        var zoomBracket: Int = 1
        var comparisonMode: HelixComparisonMode = .yesterday
    }
    @State private var dirty = DirtyState()

    var body: some View {
        if profile.helixGeometry.count < 3 {
            // Not enough data for a full helix turn
            VStack(spacing: 8) {
                Image(systemName: "dna")
                    .font(.title)
                    .foregroundStyle(SpiralColors.subtle)
                Text(loc("dna.3d.needsdata"))
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SpiralColors.surface.opacity(0.5))
            )
        } else {
            ZStack {
                // Dark background
                SpiralColors.bg

                realityContent

                overlays
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(loc("dna.3d.a11y.label"))
            .accessibilityHint(loc("dna.3d.a11y.hint"))

            // Sleep phase legend
            phaseLegend
                .padding(.top, 6)
        }
    }

    // MARK: - RealityView

    @ViewBuilder
    private var realityContent: some View {
        RealityView { content in
            let anchor = AnchorEntity()
            let (strand1, strand2) = strandRecords(mode: comparisonMode)
            let root = HelixSceneBuilder.build(from: profile, strand1Records: strand1, strand2Records: strand2)
            // RealityView's default camera sits slightly high relative to
            // the anchor origin, so a model that is mathematically centered
            // on y=0 renders with its midpoint above the visual center of
            // the view. Nudge the whole helix down so it sits in the middle
            // of the hero frame.
            root.position = SIMD3<Float>(0, -0.15, 0)
            anchor.addChild(root)

            // Directional light for glass material reflections
            let light = Entity()
            var directional = DirectionalLightComponent()
            directional.intensity = 1200
            directional.color = .white
            light.components.set(directional)
            // Diagonal angle: 45° on X, 30° on Y
            light.transform.rotation = simd_quatf(
                angle: -.pi / 4,
                axis: SIMD3<Float>(1, 0.5, 0.3)
            )
            anchor.addChild(light)

            content.add(anchor)
            manager.rootEntity = root
        } update: { content in
            guard let root = manager.rootEntity else { return }
            let totalDays = profile.nucleotides.count

            // ⓪ Comparison mode changed — rebuild geometry
            if comparisonMode != dirty.comparisonMode {
                dirty.comparisonMode = comparisonMode
                let (strand1, strand2) = strandRecords(mode: comparisonMode)
                // Remove old children
                let oldChildren = Array(root.children)
                for child in oldChildren { child.removeFromParent() }
                // Build new and snapshot children before transferring
                let rebuilt = HelixSceneBuilder.build(from: profile, strand1Records: strand1, strand2Records: strand2)
                let newChildren = Array(rebuilt.children)
                for child in newChildren { root.addChild(child) }
            }

            // ② LOD: only update materials when zoom crosses a bracket boundary
            let zoomBracket = manager.zoomScale > 1.5 ? 2 : (manager.zoomScale > 0.8 ? 1 : 0)
            if zoomBracket != dirty.zoomBracket {
                dirty.zoomBracket = zoomBracket
                HelixSceneBuilder.updateMaterialLOD(
                    root: root,
                    totalDays: totalDays,
                    zoomScale: manager.zoomScale
                )
            }

            // ③ Motif toggle: only when showPatterns actually changed
            if manager.showPatterns != dirty.showPatterns {
                dirty.showPatterns = manager.showPatterns
                HelixSceneBuilder.toggleMotifRegions(
                    root: root,
                    motifs: profile.motifs,
                    show: manager.showPatterns,
                    totalDays: totalDays
                )
            }

            // ④ Slot highlight: selected bar glows, others dim
            if manager.selectedSlot != dirty.selectedSlot {
                dirty.selectedSlot = manager.selectedSlot
                HelixSceneBuilder.highlightSlot(root: root, selectedSlot: manager.selectedSlot)
            }
        }
        .gesture(dragGesture)
        .gesture(magnifyGesture)
        .gesture(tapGesture)
        .onAppear {
            if isActive { manager.startDisplayLink() }
        }
        .onDisappear {
            manager.stopDisplayLink()
        }
        .onChange(of: isActive) { _, active in
            if active {
                manager.startDisplayLink()
            } else {
                manager.stopDisplayLink()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if isActive { manager.startDisplayLink() }
            case .inactive, .background:
                manager.stopDisplayLink()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlays: some View {
        VStack {
            // Top: comparison mode selector + patterns toggle
            HStack(spacing: 8) {
                // Comparison mode picker
                HStack(spacing: 0) {
                    ForEach(HelixComparisonMode.allCases, id: \.self) { mode in
                        Button {
                            comparisonMode = mode
                        } label: {
                            Text(comparisonModeLabel(mode))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    comparisonMode == mode
                                    ? SpiralColors.accent.opacity(0.3)
                                    : Color.clear
                                )
                                .foregroundStyle(
                                    comparisonMode == mode
                                    ? SpiralColors.accent
                                    : SpiralColors.muted
                                )
                        }
                    }
                }
                .background(Capsule().fill(SpiralColors.surface.opacity(0.85)))
                .clipShape(Capsule())
                .padding(.leading, 12)
                .padding(.top, 28)

                Spacer()

                // Patterns toggle
                if !profile.motifs.isEmpty {
                    Button {
                        manager.showPatterns.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: manager.showPatterns
                                  ? "eye.slash.fill" : "eye.fill")
                                .font(.caption)
                            Text(loc("dna.3d.patterns"))
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(SpiralColors.surface.opacity(0.85))
                        )
                        .foregroundStyle(
                            manager.showPatterns
                            ? SpiralColors.accent
                            : SpiralColors.muted
                        )
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 28)
                }
            }

            Spacer()

            // Bottom: motif legend (when patterns are shown)
            if manager.showPatterns && !profile.motifs.isEmpty {
                motifLegend
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Bottom: slot phase tooltip
            if let slot = manager.selectedSlot {
                slotTooltip(slot: slot)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.selectedSlot)
        .animation(.easeInOut(duration: 0.2), value: manager.showPatterns)
    }

    // MARK: - Slot Tooltip

    @ViewBuilder
    private func slotTooltip(slot: Int) -> some View {
        let (strand1, strand2) = strandRecords(mode: comparisonMode)
        let barsPerTurn = 10
        let dayIndex = (slot / barsPerTurn) * 7 / max(1, profile.nucleotides.count / max(1, profile.nucleotides.count / 7))
        let slotInDay = slot % barsPerTurn

        // Time range for this 30-min slot
        let record1 = strand1.isEmpty ? nil : strand1[min(strand1.count - 1, max(0, dayIndex))]
        let record2 = strand2.isEmpty ? nil : strand2[min(strand2.count - 1, max(0, dayIndex))]

        let startHour = slotStartHour(record: record1 ?? record2, slotIndex: slotInDay, totalSlots: barsPerTurn)
        let endHour = startHour + 0.5 // 30 min
        let timeText = "\(formatClockHour(startHour)) - \(formatClockHour(endHour))"

        let phase1 = phaseForSlot(record: record1, slotIndex: slotInDay, totalSlots: barsPerTurn)
        let phase2 = phaseForSlot(record: record2, slotIndex: slotInDay, totalSlots: barsPerTurn)

        let label1 = comparisonMode == .week ? loc("dna.3d.tooltip.this_week") : loc("dna.3d.tooltip.today")
        let label2 = tooltipLabel2()

        VStack(alignment: .leading, spacing: 6) {
            Text(timeText)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(SpiralColors.text)

            HStack(spacing: 6) {
                Text(label1)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .frame(width: 60, alignment: .leading)
                Text(phaseDisplayName(phase1))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
                Circle()
                    .fill(phaseDisplayColor(phase1))
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 6) {
                Text(label2)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .frame(width: 60, alignment: .leading)
                Text(phaseDisplayName(phase2))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
                Circle()
                    .fill(phaseDisplayColor(phase2))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpiralColors.surface.opacity(0.92))
        )
    }

    private func slotStartHour(record: SleepRecord?, slotIndex: Int, totalSlots: Int) -> Double {
        guard let record = record, !record.phases.isEmpty else {
            return 23.0 + Double(slotIndex) * 0.5 // default ~23:00 start
        }
        let bedtime = record.bedtimeHour
        return bedtime + Double(slotIndex) * 0.5
    }

    private func phaseForSlot(record: SleepRecord?, slotIndex: Int, totalSlots: Int) -> SleepPhase? {
        guard let record = record, !record.phases.isEmpty else { return nil }
        let idx = min(Int(Float(slotIndex) / Float(totalSlots) * Float(record.phases.count)), record.phases.count - 1)
        return record.phases[idx].phase
    }

    private func phaseDisplayName(_ phase: SleepPhase?) -> String {
        guard let phase = phase else { return "—" }
        switch phase {
        case .deep:  return loc("dna.3d.tooltip.deep")
        case .light: return loc("dna.3d.tooltip.light_nrem")
        case .rem:   return loc("dna.3d.tooltip.rem")
        case .awake: return loc("dna.3d.tooltip.wake")
        }
    }

    private func phaseDisplayColor(_ phase: SleepPhase?) -> Color {
        guard let phase = phase else { return .gray }
        return Color(hex: phase.hexColor.replacingOccurrences(of: "#", with: ""))
    }

    private func tooltipLabel2() -> String {
        switch comparisonMode {
        case .yesterday: return loc("dna.3d.tooltip.yesterday")
        case .week:      return loc("dna.3d.tooltip.last_week")
        case .best:      return loc("dna.3d.tooltip.best")
        }
    }

    private func formatClockHour(_ hour: Double) -> String {
        let h = Int(hour) % 24
        let m = Int((hour - Double(Int(hour))) * 60)
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Phase Legend

    private var phaseLegend: some View {
        VStack(spacing: 4) {
            // Strand identity
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "ebae33")).frame(width: 14, height: 4)
                    Text(comparisonMode == .week ? loc("dna.3d.tooltip.this_week") : loc("dna.3d.tooltip.today"))
                        .font(.system(size: 10)).foregroundStyle(SpiralColors.muted)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "b8bcc7")).frame(width: 14, height: 4)
                    Text(tooltipLabel2())
                        .font(.system(size: 10)).foregroundStyle(SpiralColors.muted)
                }
            }
            // Phase colors
            HStack(spacing: 12) {
                legendDot(loc("dna.3d.legend.wake"), color: Color(hex: "d4a860"))
                legendDot(loc("dna.3d.legend.rem"), color: Color(hex: "a78bfa"))
                HStack(spacing: 3) {
                    Circle().fill(Color(hex: "4a7ab5")).frame(width: 6, height: 6)
                    Text("→").font(.system(size: 7)).foregroundStyle(SpiralColors.muted)
                    Circle().fill(Color(hex: "1a2a6e")).frame(width: 6, height: 6)
                    Text(loc("dna.3d.legend.nrem")).font(.caption2).foregroundStyle(SpiralColors.muted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Motif Legend

    @ViewBuilder
    private var motifLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(profile.motifs.enumerated()), id: \.offset) { idx, motif in
                    let uiColor = HelixSceneBuilder.motifColorPalette[idx % HelixSceneBuilder.motifColorPalette.count]
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor))
                            .frame(width: 8, height: 8)
                        Text(localizedMotifName(motif.name))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SpiralColors.text)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(SpiralColors.surface.opacity(0.85))
            )
        }
    }

    private func localizedMotifName(_ engineName: String) -> String {
        let key = "dna.motif.name.\(engineName.lowercased())"
        let result = loc(key)
        return result == key ? engineName : result
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !manager.isInteracting {
                    manager.isInteracting = true
                    manager.dragStart = value.translation
                    return
                }
                let deltaX = Float(value.translation.width - manager.dragStart.width)
                let deltaY = Float(value.translation.height - manager.dragStart.height)
                manager.applyDrag(translationX: deltaX * 0.5, translationY: deltaY * 0.5)
                manager.dragStart = value.translation
            }
            .onEnded { _ in
                manager.isInteracting = false
                manager.dragStart = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                manager.isInteracting = true
                let mag = Float(value.magnification) * manager.baseZoom
                manager.applyZoom(mag)
            }
            .onEnded { value in
                manager.baseZoom = manager.zoomScale
                manager.isInteracting = false
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                let entity = value.entity
                var name = entity.name

                // Walk up parent chain to find bar entity (in case child is hit)
                var current: Entity? = entity
                while let e = current {
                    if e.name.hasPrefix("bar_") && !e.name.contains("_h") && !e.name.contains("_c") {
                        name = e.name
                        break
                    }
                    current = e.parent
                }

                guard name.hasPrefix("bar_") else {
                    // Tapped non-bar entity = deselect
                    manager.selectedSlot = nil
                    manager.selectedWeek = nil
                    return
                }

                // Parse index from "bar_42"
                let parts = name.components(separatedBy: "_")
                guard parts.count >= 2, let slotIndex = Int(parts[1]) else {
                    manager.selectedSlot = nil
                    manager.selectedWeek = nil
                    return
                }

                if manager.selectedSlot == slotIndex {
                    manager.selectedSlot = nil
                    manager.selectedWeek = nil
                } else {
                    manager.selectedSlot = slotIndex
                    manager.selectedWeek = slotIndex / 10
                }
            }
    }

    // Auto-rotation and transform handled by CADisplayLink in HelixInteractionManager

    // MARK: - Comparison Mode

    private func strandRecords(mode: HelixComparisonMode) -> (strand1: [SleepRecord], strand2: [SleepRecord]) {
        guard records.count >= 2 else { return (records, records) }

        switch mode {
        case .yesterday:
            // Strand 1 = last night, Strand 2 = night before
            let last = Array(records.suffix(1))
            let prev = Array(records.suffix(2).prefix(1))
            return (last, prev)

        case .week:
            // Strand 1 = this week (last 7), Strand 2 = previous week (7 before that)
            let thisWeek = Array(records.suffix(7))
            let prevWeek = records.count >= 14
                ? Array(records.suffix(14).prefix(7))
                : Array(records.prefix(min(7, records.count)))
            return (thisWeek, prevWeek)

        case .best:
            // Strand 1 = last night, Strand 2 = best night (highest sleep duration)
            let last = Array(records.suffix(1))
            let best: [SleepRecord]
            if let bestRecord = records.max(by: { $0.sleepDuration < $1.sleepDuration }) {
                best = [bestRecord]
            } else {
                best = last
            }
            return (last, best)
        }
    }

    private func comparisonModeLabel(_ mode: HelixComparisonMode) -> String {
        switch mode {
        case .yesterday: return loc("dna.3d.mode.yesterday")
        case .week:      return loc("dna.3d.mode.week")
        case .best:      return loc("dna.3d.mode.best")
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Comparison Mode Enum

enum HelixComparisonMode: String, CaseIterable {
    case yesterday
    case week
    case best
}
