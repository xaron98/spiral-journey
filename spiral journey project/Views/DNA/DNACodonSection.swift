import SwiftUI
import SpiralKit

/// "Arquitectura del sueño" — intra-night codon analysis results.
/// Only shown when Apple Watch provides sleep stage data.
struct DNACodonSection: View {

    let codonResult: SleepCodonAnalyzer.MultiNightCodonResult

    @Environment(\.languageBundle) private var bundle

    private var integrityPercent: Int { Int(codonResult.meanIntegrity * 100) }

    private var integrityColor: Color {
        if codonResult.meanIntegrity >= 0.7 { return SpiralColors.good }
        if codonResult.meanIntegrity >= 0.5 { return SpiralColors.moderate }
        return SpiralColors.poor
    }

    private var trendIcon: String {
        if codonResult.trend > 0.01 { return "arrow.up.right" }
        if codonResult.trend < -0.01 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var trendLabel: String {
        if codonResult.trend > 0.01 { return loc("dna.codon.trend.improving") }
        if codonResult.trend < -0.01 { return loc("dna.codon.trend.declining") }
        return loc("dna.codon.trend.stable")
    }

    private var trendColor: Color {
        if codonResult.trend > 0.01 { return SpiralColors.good }
        if codonResult.trend < -0.01 { return SpiralColors.poor }
        return SpiralColors.muted
    }

    @State private var showCodonHelp = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundStyle(SpiralColors.accent)
                Text(loc("dna.codon.header"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
                Label(trendLabel, systemImage: trendIcon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(trendColor)
                Button { showCodonHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(SpiralColors.muted)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showCodonHelp) {
                CodonHelpSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }

            // Integrity score
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(integrityPercent)%")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(integrityColor)
                Text(loc("dna.codon.integrity"))
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
            }

            // Mini bar showing nightly integrity
            codonMiniBar

            // Worst disruption (if any)
            if let worst = codonResult.mostCommonDisruption {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(SpiralColors.poor)
                    Text(String(format: loc("dna.codon.disruption"), readableCodon(worst)))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Mini Bar

    @Environment(SpiralStore.self) private var store

    private var codonMiniBar: some View {
        let nights = Array(codonResult.nightlyResults.suffix(14))
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(night.integrityScore))
                        .frame(height: max(4, CGFloat(night.integrityScore) * 20))
                }
            }
            .frame(height: 20, alignment: .bottom)

            // Day initials below bars
            HStack(spacing: 2) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    Text(dayInitial(for: night.day))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(SpiralColors.subtle)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dayInitial(for day: Int) -> String {
        guard let record = store.records.first(where: { $0.day == day }) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        return String(formatter.string(from: record.date).prefix(1)).uppercased()
    }

    private func barColor(_ integrity: Double) -> Color {
        if integrity >= 0.7 { return Color(hex: "34d399") }  // green — always visible
        if integrity >= 0.5 { return Color(hex: "fbbf24") }  // amber — always visible
        return Color(hex: "f87171")                           // red — always visible
    }

    // MARK: - Helpers

    /// Convert codon code to readable format: "RWL" → "REM → Despierto → Ligero"
    private func readableCodon(_ code: String) -> String {
        code.map { char -> String in
            switch char {
            case "W": return loc("dna.codon.phase.awake")
            case "L": return loc("dna.codon.phase.light")
            case "D": return loc("dna.codon.phase.deep")
            case "R": return loc("dna.codon.phase.rem")
            default: return String(char)
            }
        }.joined(separator: " → ")
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Codon Help Sheet

private struct CodonHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpItem(
                        icon: "waveform.badge.magnifyingglass",
                        title: loc("codon.help.what.title"),
                        body: loc("codon.help.what.body")
                    )
                    helpItem(
                        icon: "chart.bar.fill",
                        title: loc("codon.help.bars.title"),
                        body: loc("codon.help.bars.body")
                    )
                    helpItem(
                        icon: "exclamationmark.triangle",
                        title: loc("codon.help.disruption.title"),
                        body: loc("codon.help.disruption.body")
                    )
                    Text(loc("codon.help.disclaimer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("codon.help.title"))
            .navigationBarTitleDisplayMode(.inline)
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

    private func helpItem(icon: String, title: String, body: String) -> some View {
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
