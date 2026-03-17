import SwiftUI
import RealityKit
import SpiralKit

/// Interactive 3D double-helix view of a SleepDNA profile using RealityKit.
///
/// Supports drag-to-rotate, pinch-to-zoom, tap-to-select-week, and motif pattern toggling.
@available(iOS 18.0, *)
struct HelixRealityView: View {

    let profile: SleepDNAProfile

    @Environment(\.languageBundle) private var bundle
    @State private var manager = HelixInteractionManager()
    @State private var helixRoot: Entity?

    /// Baseline zoom before the current pinch gesture.
    @State private var baseZoom: Float = 1.0
    /// Accumulated drag for the current gesture.
    @State private var dragStart: CGSize = .zero

    var body: some View {
        ZStack {
            // Dark background
            SpiralColors.bg

            realityContent

            overlays
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - RealityView

    @ViewBuilder
    private var realityContent: some View {
        RealityView { content in
            let anchor = AnchorEntity()
            let root = HelixSceneBuilder.build(from: profile)
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
        .gesture(dragGesture)
        .gesture(magnifyGesture)
        .gesture(tapGesture)
        .onAppear {
            startAutoRotation()
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
                                .font(.system(size: 11))
                            Text(loc("dna.3d.patterns"))
                                .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)

                if let sim = similarity {
                    Text("\(Int(sim * 100))% \(loc("dna.3d.similar"))")
                        .font(.system(size: 12))
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
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.subtle)
                    Text(motif.name)
                        .font(.system(size: 12, weight: .medium))
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
        DragGesture()
            .onChanged { value in
                manager.isInteracting = true
                let deltaX = Float(value.translation.width - dragStart.width)
                let deltaY = Float(value.translation.height - dragStart.height)
                manager.applyDrag(translationX: deltaX, translationY: deltaY)
                dragStart = value.translation
            }
            .onEnded { _ in
                manager.isInteracting = false
                dragStart = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                manager.isInteracting = true
                let mag = Float(value.magnification) * baseZoom
                manager.applyZoom(mag)
            }
            .onEnded { value in
                baseZoom = manager.zoomScale
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

    // MARK: - Auto-rotation Timer

    private func startAutoRotation() {
        // Use a display-link-style timer at ~30fps
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                manager.tickAutoRotation()
            }
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
