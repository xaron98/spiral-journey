import SwiftUI
import SpiralKit

/// Educational info sheet explaining the SleepDNA metaphor and each section
/// of the DNA Insights view. Mirrors the NeuroSpiral info sheet pattern.
struct DNAInfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // 1. The big idea
                    infoSection(
                        icon: "gyroscope", iconColor: .purple,
                        title: loc("dna.info.idea.title"),
                        body: loc("dna.info.idea.body")
                    )

                    // 2. Nucleotides
                    infoSection(
                        icon: "circle.hexagongrid.fill", iconColor: .teal,
                        title: loc("dna.info.nucleotide.title"),
                        body: loc("dna.info.nucleotide.body")
                    )

                    // 3. The helix
                    infoSection(
                        icon: "helix", iconColor: .indigo,
                        title: loc("dna.info.helix.title"),
                        body: loc("dna.info.helix.body")
                    )

                    // 3b. Reading the 3D helix bars
                    infoSection(
                        icon: "cylinder.split.1x2", iconColor: .blue,
                        title: loc("dna.info.helix3d.title"),
                        body: loc("dna.info.helix3d.body")
                    )

                    // 4. Motifs & mutations
                    infoSection(
                        icon: "waveform.badge.magnifyingglass", iconColor: .orange,
                        title: loc("dna.info.motifs.title"),
                        body: loc("dna.info.motifs.body")
                    )

                    // 5. Alignment & prediction
                    infoSection(
                        icon: "arrow.left.and.right.text.vertical", iconColor: .cyan,
                        title: loc("dna.info.alignment.title"),
                        body: loc("dna.info.alignment.body")
                    )

                    // 6. Base pairs
                    infoSection(
                        icon: "link", iconColor: .pink,
                        title: loc("dna.info.basepairs.title"),
                        body: loc("dna.info.basepairs.body")
                    )

                    // 7. Codons
                    infoSection(
                        icon: "text.word.spacing", iconColor: .mint,
                        title: loc("dna.info.codons.title"),
                        body: loc("dna.info.codons.body")
                    )

                    // 8. Health markers
                    infoSection(
                        icon: "heart.text.clipboard", iconColor: .red,
                        title: loc("dna.info.health.title"),
                        body: loc("dna.info.health.body")
                    )

                    // 9. Tiers
                    infoSection(
                        icon: "chart.bar.fill", iconColor: .green,
                        title: loc("dna.info.tiers.title"),
                        body: loc("dna.info.tiers.body")
                    )

                    // 10. Bridge to NeuroSpiral
                    infoSection(
                        icon: "cube.transparent", iconColor: .purple,
                        title: loc("dna.info.bridge.title"),
                        body: loc("dna.info.bridge.body")
                    )

                    // 11. Not real DNA
                    infoSection(
                        icon: "exclamationmark.triangle", iconColor: SpiralColors.muted,
                        title: loc("dna.info.disclaimer.title"),
                        body: loc("dna.info.disclaimer.body")
                    )

                    Divider()

                    Text(loc("dna.info.reference"))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("dna.info.nav"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func infoSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SpiralColors.text)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(SpiralColors.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
