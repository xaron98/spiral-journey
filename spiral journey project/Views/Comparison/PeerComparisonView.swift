import SwiftUI
import SpiralKit

/// Ephemeral peer sleep comparison via Multipeer Connectivity.
/// Shows 3 states: searching (radar animation), connected (side-by-side cards), disconnected.
struct PeerComparisonView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(\.dismiss) private var dismiss

    @State private var manager = PeerComparisonManager()

    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                switch manager.state {
                case .idle, .searching:
                    searchingView
                case .connected:
                    connectedView
                case .disconnected:
                    disconnectedView
                }
            }
            .navigationTitle(String(localized: "comparison.title", bundle: bundle))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        manager.stopSearching()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
        .onAppear {
            let payload = ComparisonPayload.build(
                alias: store.comparisonAlias,
                analysis: store.analysis,
                dnaProfile: store.dnaProfile,
                records: store.records
            )
            manager.startSearching(alias: store.comparisonAlias, myPayload: payload)
        }
        .onDisappear {
            manager.stopSearching()
        }
    }

    // MARK: - Searching State

    private var searchingView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Pulsating radar animation
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    PulseCircle(delay: Double(i) * 0.8)
                }
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(SpiralColors.accent)
            }
            .frame(width: 200, height: 200)

            VStack(spacing: 8) {
                Text(String(localized: "comparison.searching", bundle: bundle))
                    .font(.headline.monospaced())
                    .foregroundStyle(SpiralColors.text)
                    .multilineTextAlignment(.center)

                Text(String(format: String(localized: "comparison.sharingAs", bundle: bundle),
                            store.comparisonAlias))
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Connected State

    private var connectedView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                headerCard
                comparisonCards
                periodogramCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                // You
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                    Text(store.comparisonAlias)
                        .font(.subheadline.weight(.medium).monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Text(String(format: String(localized: "comparison.days", bundle: bundle),
                                store.records.count))
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)

                // Peer
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                    Text(manager.peerAlias ?? "—")
                        .font(.subheadline.weight(.medium).monospaced())
                        .foregroundStyle(SpiralColors.text)
                    if let peer = manager.peerPayload {
                        Text(String(format: String(localized: "comparison.days", bundle: bundle),
                                    peer.recordCount))
                            .font(.caption2.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .glassPanel(tint: SpiralColors.accent)
    }

    @ViewBuilder
    private var comparisonCards: some View {
        if let peer = manager.peerPayload {
            let myPayload = buildMyPayload()

            comparisonRow(
                label: String(localized: "comparison.metric.consistency", bundle: bundle),
                myValue: Double(myPayload.consistencyScore),
                peerValue: Double(peer.consistencyScore),
                format: "%.0f",
                unit: "%"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.duration", bundle: bundle),
                myValue: myPayload.meanDuration,
                peerValue: peer.meanDuration,
                format: "%.1f",
                unit: "h"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.regularity", bundle: bundle),
                myValue: myPayload.sleepRegularityIndex,
                peerValue: peer.sleepRegularityIndex,
                format: "%.0f",
                unit: ""
            )
            comparisonRow(
                label: String(localized: "comparison.metric.socialJetlag", bundle: bundle),
                myValue: myPayload.socialJetlag,
                peerValue: peer.socialJetlag,
                format: "%.1f",
                unit: "h"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.chronotype", bundle: bundle),
                myText: chronotypeDisplay(myPayload.chronotype),
                peerText: chronotypeDisplay(peer.chronotype)
            )
            comparisonRow(
                label: String(localized: "comparison.metric.acrophase", bundle: bundle),
                myValue: myPayload.meanAcrophase,
                peerValue: peer.meanAcrophase,
                format: "%.1f",
                unit: "h"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.bedtime", bundle: bundle),
                myValue: myPayload.meanBedtime,
                peerValue: peer.meanBedtime,
                format: "%.1f",
                unit: "h"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.wake", bundle: bundle),
                myValue: myPayload.meanWake,
                peerValue: peer.meanWake,
                format: "%.1f",
                unit: "h"
            )
            comparisonRow(
                label: String(localized: "comparison.metric.coherence", bundle: bundle),
                myValue: myPayload.circadianCoherence,
                peerValue: peer.circadianCoherence,
                format: "%.2f",
                unit: ""
            )
            comparisonRow(
                label: String(localized: "comparison.metric.fragmentation", bundle: bundle),
                myValue: myPayload.fragmentationScore,
                peerValue: peer.fragmentationScore,
                format: "%.2f",
                unit: ""
            )
        }
    }

    @ViewBuilder
    private var periodogramCard: some View {
        if let peer = manager.peerPayload {
            let myPayload = buildMyPayload()
            let myPeaks = myPayload.periodogramPeaks
            let peerPeaks = peer.periodogramPeaks

            if !myPeaks.isEmpty || !peerPeaks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "comparison.metric.periodogram", bundle: bundle))
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(SpiralColors.muted)
                        .tracking(0.5)

                    // Show peaks as horizontal bars grouped by label
                    let allPeaks = combinePeaks(mine: myPeaks, peer: peerPeaks)
                    let maxPower = allPeaks.map { max($0.myPower, $0.peerPower) }.max() ?? 1.0

                    ForEach(allPeaks, id: \.label) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label)
                                .font(.caption2.monospaced())
                                .foregroundStyle(SpiralColors.subtle)

                            HStack(spacing: 6) {
                                // My bar
                                GeometryReader { geo in
                                    let fraction = maxPower > 0 ? entry.myPower / maxPower : 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.blue.opacity(0.7))
                                        .frame(width: geo.size.width * fraction)
                                }
                                .frame(height: 8)

                                Text(String(format: "%.2f", entry.myPower))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color.blue)
                                    .frame(width: 40, alignment: .trailing)
                            }

                            HStack(spacing: 6) {
                                GeometryReader { geo in
                                    let fraction = maxPower > 0 ? entry.peerPower / maxPower : 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: geo.size.width * fraction)
                                }
                                .frame(height: 8)

                                Text(String(format: "%.2f", entry.peerPower))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color.orange)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(16)
                .glassPanel()
            }
        }
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(SpiralColors.muted)

            Text(String(localized: "comparison.disconnected", bundle: bundle))
                .font(.headline.monospaced())
                .foregroundStyle(SpiralColors.text)

            Button {
                let payload = ComparisonPayload.build(
                    alias: store.comparisonAlias,
                    analysis: store.analysis,
                    dnaProfile: store.dnaProfile,
                    records: store.records
                )
                manager.startSearching(alias: store.comparisonAlias, myPayload: payload)
            } label: {
                Text(String(localized: "comparison.searchAgain", bundle: bundle))
                    .font(.subheadline.weight(.medium).monospaced())
                    .foregroundStyle(SpiralColors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SpiralColors.accent.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Comparison Row (Numeric)

    private func comparisonRow(
        label: String,
        myValue: Double,
        peerValue: Double,
        format: String = "%.1f",
        unit: String = ""
    ) -> some View {
        let maxVal = max(abs(myValue), abs(peerValue), 0.001)

        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.muted)
                .tracking(0.5)

            HStack(spacing: 8) {
                Text(String(format: format, myValue) + unit)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Color.blue)
                    .frame(width: 56, alignment: .trailing)

                GeometryReader { geo in
                    let myFrac = abs(myValue) / maxVal
                    let peerFrac = abs(peerValue) / maxVal
                    let halfW = geo.size.width / 2

                    ZStack(alignment: .leading) {
                        // My bar (left-aligned, blue)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: halfW * myFrac, height: 12)

                        // Peer bar (left-aligned, orange)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: halfW * peerFrac, height: 12)
                            .offset(y: 14)
                    }
                }
                .frame(height: 28)

                Text(String(format: format, peerValue) + unit)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Color.orange)
                    .frame(width: 56, alignment: .leading)
            }
        }
        .padding(12)
        .glassPanel()
    }

    // MARK: - Comparison Row (Text)

    private func comparisonRow(
        label: String,
        myText: String,
        peerText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.muted)
                .tracking(0.5)

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text(myText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(SpiralColors.text)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(peerText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(SpiralColors.text)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .glassPanel()
    }

    // MARK: - Helpers

    private func buildMyPayload() -> ComparisonPayload {
        ComparisonPayload.build(
            alias: store.comparisonAlias,
            analysis: store.analysis,
            dnaProfile: store.dnaProfile,
            records: store.records
        )
    }

    private func chronotypeDisplay(_ raw: String) -> String {
        switch raw {
        case "morning":      return String(localized: "chronotype.morning", bundle: bundle)
        case "evening":      return String(localized: "chronotype.evening", bundle: bundle)
        case "intermediate": return String(localized: "chronotype.intermediate", bundle: bundle)
        default:             return raw
        }
    }

    /// Combine my peaks and peer peaks by period label into a unified list.
    private func combinePeaks(mine: [PeakSummary], peer: [PeakSummary]) -> [CombinedPeak] {
        var map: [String: (my: Double, peer: Double)] = [:]

        for p in mine {
            let label = p.label ?? String(format: "%.1fh", p.period)
            map[label, default: (0, 0)].my = p.power
        }
        for p in peer {
            let label = p.label ?? String(format: "%.1fh", p.period)
            map[label, default: (0, 0)].peer = p.power
        }

        return map.map { CombinedPeak(label: $0.key, myPower: $0.value.my, peerPower: $0.value.peer) }
            .sorted { $0.label < $1.label }
    }
}

// MARK: - Supporting Types

private struct CombinedPeak {
    let label: String
    let myPower: Double
    let peerPower: Double
}

/// Pulsating circle for the radar search animation.
private struct PulseCircle: View {
    let delay: Double

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0.8

    var body: some View {
        Circle()
            .stroke(SpiralColors.accent.opacity(opacity), lineWidth: 1.5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 2.4)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 1.2
                    opacity = 0
                }
            }
    }
}
