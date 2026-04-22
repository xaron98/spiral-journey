import SwiftUI

/// Explains what Sleep DNA is and how it works — shown from the ? button in DNAInsightsView.
struct DNAHelpSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Hero
                    VStack(spacing: 8) {
                        Text("🧬")
                            .font(.system(size: 48))
                        Text(loc("dna.help.title"))
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(loc("dna.help.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // What is it
                    helpSection(
                        icon: "waveform.path.ecg",
                        title: loc("dna.help.what.title"),
                        body: loc("dna.help.what.body")
                    )

                    // How it works
                    helpSection(
                        icon: "gearshape.2",
                        title: loc("dna.help.how.title"),
                        body: loc("dna.help.how.body")
                    )

                    // The helix
                    helpSection(
                        icon: "view.3d",
                        title: loc("dna.help.helix.title"),
                        body: loc("dna.help.helix.body")
                    )

                    // What it detects
                    helpSection(
                        icon: "magnifyingglass",
                        title: loc("dna.help.detects.title"),
                        body: loc("dna.help.detects.body")
                    )

                    // Data needed
                    helpSection(
                        icon: "clock.badge.checkmark",
                        title: loc("dna.help.data.title"),
                        body: loc("dna.help.data.body")
                    )

                    // Experimental methodology
                    helpSection(
                        icon: "flask",
                        title: loc("dna.help.experimental.title"),
                        body: loc("dna.help.experimental.body")
                    )

                    // Disclaimer
                    Text(loc("dna.help.disclaimer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private func helpSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
