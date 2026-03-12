import SwiftUI
import SpiralKit

/// Composite score arc + key circadian stats.
struct WatchStatsView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private var app: String { store.appearance }

    var body: some View {
        ZStack {
            SpiralColors.bg(app).ignoresSafeArea()
        ScrollView {
            VStack(spacing: 8) {

                // Score arc
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(SpiralColors.border(app), lineWidth: 7)
                        .rotationEffect(.degrees(135))

                    Circle()
                        .trim(from: 0, to: 0.75 * Double(store.compositeScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .animation(.easeOut(duration: 0.8), value: store.compositeScore)

                    VStack(spacing: 0) {
                        Text("\(store.compositeScore)")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(scoreColor)
                        Text(scoreLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(SpiralColors.muted(app))
                    }
                }
                .frame(width: 80, height: 80)
                .padding(.top, 4)

                // Consistency glance (shown only when data is available)
                if let cons = store.analysis.consistency {
                    consistencyGlance(cons)
                    Divider().background(SpiralColors.border(app))
                } else {
                    Divider().background(SpiralColors.border(app))
                }

                statRow("SRI",        value: String(format: "%.0f%%", store.sri))
                statRow(String(localized: "watch.stats.acrophase", bundle: bundle),  value: formatHour(store.acrophase))
                statRow(String(localized: "watch.stats.sleep",      bundle: bundle), value: String(format: "%.1fh", store.sleepDuration))
            }
            .padding(.horizontal, 6)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle(String(localized: "watch.stats.title", bundle: bundle))
        } // ZStack
    }

    private var scoreColor: Color {
        switch store.compositeScore {
        case 80...: return SpiralColors.accent
        case 60...: return SpiralColors.moderate
        default:    return SpiralColors.poor
        }
    }

    private var scoreLabel: String {
        switch store.compositeScore {
        case 80...: return String(localized: "watch.score.excellent", bundle: bundle)
        case 60...: return String(localized: "watch.score.good",      bundle: bundle)
        case 40...: return String(localized: "watch.score.moderate",  bundle: bundle)
        default:    return String(localized: "watch.score.attention", bundle: bundle)
        }
    }

    @ViewBuilder
    private func consistencyGlance(_ cons: SpiralConsistencyScore) -> some View {
        HStack(spacing: 6) {
            // Mini ring
            ZStack {
                Circle()
                    .stroke(SpiralColors.border(app), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(cons.score) / 100)
                    .stroke(Color(hex: cons.label.hexColor),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "watch.stats.consistency", bundle: bundle))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted(app))
                Text(cons.label.displayText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: cons.label.hexColor))
            }

            Spacer()

            Text("\(cons.score)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: cons.label.hexColor))
        }
        .padding(.vertical, 2)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SpiralColors.muted(app))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.text(app))
        }
    }

    private func formatHour(_ h: Double) -> String {
        let h24 = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
    }
}
