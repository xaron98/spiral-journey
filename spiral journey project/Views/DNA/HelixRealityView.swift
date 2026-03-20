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
    @State private var helixRoot: Entity?

    /// Baseline zoom before the current pinch gesture.
    @State private var baseZoom: Float = 1.0
    /// Accumulated drag for the current gesture.
    @State private var dragStart: CGSize = .zero

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
            content.add(anchor)
            helixRoot = root
        } update: { content in
            guard let root = helixRoot else { return }

            // Apply interaction transform
            root.transform = manager.sceneTransform

            // Handle motif toggling
            HelixSceneBuilder.toggleMotifRegions(
                root: root,
                motifs: profile.motifs,
                show: manager.showPatterns,
                totalDays: profile.nucleotides.count
            )

            // Handle week highlights
            if let week = manager.selectedWeek {
                HelixSceneBuilder.resetHighlights(
                    root: root,
                    totalDays: profile.nucleotides.count
                )
                HelixSceneBuilder.highlightSimilarWeeks(
                    root: root,
                    selectedWeek: week,
                    alignments: profile.alignments,
                    totalDays: profile.nucleotides.count
                )
            } else {
                HelixSceneBuilder.resetHighlights(
                    root: root,
                    totalDays: profile.nucleotides.count
                )
            }
        }
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(tapGesture)
        .contentShape(Rectangle())  // ensure full area is gesture-tappable
        .onAppear {
            startAutoRotation()
        }
        .onDisappear {
            autoRotationTimer?.invalidate()
            autoRotationTimer = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if autoRotationTimer == nil { startAutoRotation() }
            case .inactive, .background:
                autoRotationTimer?.invalidate()
                autoRotationTimer = nil
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

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !manager.isInteracting {
                    // First frame: record start, don't apply yet
                    manager.isInteracting = true
                    isInteractingWith3D = true
                    dragStart = value.translation
                    return
                }
                let deltaX = Float(value.translation.width - dragStart.width)
                let deltaY = Float(value.translation.height - dragStart.height)
                manager.applyDrag(translationX: deltaX * 0.5, translationY: deltaY * 0.5)
                dragStart = value.translation
            }
            .onEnded { _ in
                manager.isInteracting = false
                isInteractingWith3D = false
                dragStart = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                manager.isInteracting = true
                isInteractingWith3D = true
                let mag = Float(value.magnification) * baseZoom
                manager.applyZoom(mag)
            }
            .onEnded { value in
                baseZoom = manager.zoomScale
                manager.isInteracting = false
                isInteractingWith3D = false
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

    // MARK: - Auto-rotation Timer

    @State private var autoRotationTimer: Timer?

    private func startAutoRotation() {
        // Invalidate any existing timer first
        autoRotationTimer?.invalidate()
        // Low frequency (10fps) to save memory and CPU
        autoRotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { _ in
            Task { @MainActor [weak manager] in
                manager?.tickAutoRotation()
            }
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
