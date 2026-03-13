import SwiftUI
import SpiralKit

/// Displays 9 computed statistics cards and circadian disorder signatures.
struct StatsPanelView: View {

    let records: [SleepRecord]
    @Environment(\.languageBundle) private var bundle
    @State private var showGlossary = false

    private var stats: SleepStats {
        SleepStatistics.calculateStats(records)
    }

    private var signatures: [DisorderSignature] {
        DisorderDetection.detect(from: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelTitle(title: String(localized: "stats.title", bundle: bundle))
                Spacer()
                Button {
                    showGlossary = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(SpiralColors.subtle)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showGlossary) {
                StatsGlossarySheet(bundle: bundle)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatCard(String(localized: "stats.card.acrophase", bundle: bundle),
                         value: SleepStatistics.formatHour(stats.meanAcrophase),
                         sub: String(localized: "stats.acrophase.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.acroSigma", bundle: bundle),
                         value: String(format: "±%.1fh", stats.stdAcrophase),
                         sub: String(localized: "stats.acroSigma.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.amplitude", bundle: bundle),
                         value: String(format: "%.2f", stats.meanAmplitude),
                         sub: String(localized: "stats.amplitude.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.rhythm", bundle: bundle),
                         value: String(format: "%.0f%%", stats.rhythmStability * 100),
                         sub: String(localized: "stats.rhythm.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.sri", bundle: bundle),
                         value: String(format: "%.0f%%", stats.sri),
                         sub: String(localized: "stats.sri.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.socialJL", bundle: bundle),
                         value: String(format: "%.0f min", stats.socialJetlag),
                         sub: String(localized: "stats.socialJL.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.wkndAmp", bundle: bundle),
                         value: String(format: "%.2f", stats.weekendAmp),
                         sub: String(format: "%.0f%% drop", max(0, stats.ampDrop)))
                StatCard(String(localized: "stats.card.sleep", bundle: bundle),
                         value: String(format: "%.1fh", stats.meanSleepDuration),
                         sub: String(localized: "stats.sleep.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.r2", bundle: bundle),
                         value: String(format: "%.2f", stats.meanR2),
                         sub: String(localized: "stats.r2.sub", bundle: bundle))
            }

            if !signatures.isEmpty {
                Divider().background(SpiralColors.border)
                PanelTitle(title: String(localized: "stats.pattern.title", bundle: bundle))
                ForEach(signatures) { sig in
                    SignatureBadge(signature: sig)
                }
            }
        }
        .panelStyle()
    }
}

// MARK: - Stats Glossary Sheet

private struct StatsGlossarySheet: View {
    let bundle: Bundle
    @Environment(\.dismiss) private var dismiss

    private struct GlossaryItem: Identifiable {
        let id = UUID()
        let term: String
        let definition: String
        let icon: String
    }

    private var items: [GlossaryItem] {
        [
            GlossaryItem(
                term: NSLocalizedString("stats.card.acrophase", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.acrophase", bundle: bundle, comment: ""),
                icon: "clock"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.acroSigma", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.acroSigma", bundle: bundle, comment: ""),
                icon: "plusminus"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.amplitude", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.amplitude", bundle: bundle, comment: ""),
                icon: "waveform"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.rhythm", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.rhythm", bundle: bundle, comment: ""),
                icon: "repeat"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.sri", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.sri", bundle: bundle, comment: ""),
                icon: "calendar"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.socialJL", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.socialJL", bundle: bundle, comment: ""),
                icon: "calendar.badge.exclamationmark"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.wkndAmp", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.wkndAmp", bundle: bundle, comment: ""),
                icon: "moon.stars"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.sleep", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.sleep", bundle: bundle, comment: ""),
                icon: "bed.double"
            ),
            GlossaryItem(
                term: NSLocalizedString("stats.card.r2", bundle: bundle, comment: ""),
                definition: NSLocalizedString("stats.glossary.r2", bundle: bundle, comment: ""),
                icon: "chart.line.uptrend.xyaxis"
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(SpiralColors.accent)
                                    .frame(width: 20)
                                Text(item.term)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SpiralColors.text)
                            }
                            Text(item.definition)
                                .font(.system(size: 12))
                                .foregroundStyle(SpiralColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                                .padding(.leading, 28)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        Divider()
                            .background(SpiralColors.border)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("stats.glossary.title", bundle: bundle, comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("stats.glossary.done", bundle: bundle, comment: "")) {
                        dismiss()
                    }
                    .foregroundStyle(SpiralColors.accent)
                }
            }
        }
    }
}

private struct SignatureBadge: View {
    let signature: DisorderSignature

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: signature.hexColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(signature.fullLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Text(String(format: "%.0f%%", signature.confidence * 100))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SpiralColors.subtle)
                }
                Text(signature.description)
                    .font(.system(size: 9))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
