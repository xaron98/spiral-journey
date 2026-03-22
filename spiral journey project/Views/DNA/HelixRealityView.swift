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

    @Environment(\.languageBundle) private var bundle
    @Environment(\.scenePhase) private var scenePhase
    @State private var manager = HelixInteractionManager()

    // manager.baseZoom and manager.dragStart stored in manager (@ObservationIgnored) to avoid @State re-renders

    // ── Dirty-tracking: skip expensive ops when only transform changed ──
    private final class DirtyState {
        var selectedWeek: Int? = nil
        var showPatterns: Bool = false
        var zoomBracket: Int = 1
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
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(loc("dna.3d.a11y.label"))
            .accessibilityHint(loc("dna.3d.a11y.hint"))
        }
    }

    // MARK: - RealityView

    @ViewBuilder
    private var realityContent: some View {
        RealityView { content in
            let anchor = AnchorEntity()
            let root = HelixSceneBuilder.build(from: profile, records: records)
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

            // ① Transform is handled by CADisplayLink at 60fps — NOT here.
            // This update: closure only runs when observed state changes
            // (selectedWeek, showPatterns).

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

            // ④ Week highlights: only when selection changed
            if manager.selectedWeek != dirty.selectedWeek {
                dirty.selectedWeek = manager.selectedWeek
                if let week = manager.selectedWeek {
                    HelixSceneBuilder.resetHighlights(root: root, totalDays: totalDays)
                    HelixSceneBuilder.highlightSimilarWeeks(
                        root: root,
                        selectedWeek: week,
                        alignments: profile.alignments,
                        totalDays: totalDays
                    )
                } else {
                    HelixSceneBuilder.resetHighlights(root: root, totalDays: totalDays)
                }
            }
        }
        .gesture(dragGesture)
        .gesture(magnifyGesture)
        .simultaneousGesture(tapGesture)
        .onAppear {
            manager.startDisplayLink()
        }
        .onDisappear {
            manager.stopDisplayLink()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                manager.startDisplayLink()
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
            // Top-right: patterns toggle (only if motifs exist)
            if !profile.motifs.isEmpty {
                HStack {
                    Spacer()
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
                    .padding(.top, 12)
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

            // Bottom: week info card
            if let week = manager.selectedWeek {
                weekInfoCard(week: week)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.selectedWeek)
        .animation(.easeInOut(duration: 0.2), value: manager.showPatterns)
    }

    // MARK: - Week Info Card

    @ViewBuilder
    private func weekInfoCard(week: Int) -> some View {
        let similarity = profile.alignments
            .first(where: { $0.weekIndex == week })?.similarity

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(loc("dna.3d.week")) \(week + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)

                if let sim = similarity {
                    Text("\(Int(sim * 100))% \(loc("dna.3d.similar"))")
                        .font(.footnote)
                        .foregroundStyle(SpiralColors.muted)
                }
            }

            Spacer()

            // Show motif name if this week belongs to one
            if let motif = profile.motifs.first(where: {
                $0.instanceWeekIndices.contains(week)
            }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(loc("dna.3d.pattern"))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.subtle)
                    Text(motif.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SpiralColors.accent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpiralColors.surface.opacity(0.9))
        )
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
            .onEnded { value in
                // Simplified: cycle through weeks based on tap Y position
                let fraction = value.location.y / 400.0
                let totalWeeks = max(1, profile.nucleotides.count / 7)
                let tappedWeek = Int(fraction * CGFloat(totalWeeks))
                let clampedWeek = max(0, min(totalWeeks - 1, tappedWeek))

                if manager.selectedWeek == clampedWeek {
                    manager.selectedWeek = nil
                } else {
                    manager.selectedWeek = clampedWeek
                }
            }
    }

    // Auto-rotation and transform handled by CADisplayLink in HelixInteractionManager

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
