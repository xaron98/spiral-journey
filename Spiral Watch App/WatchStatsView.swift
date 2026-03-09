import SwiftUI
import SpiralKit

/// Key circadian stats on the watch: composite score, SRI, acrophase, duration.
struct WatchStatsView: View {

    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Composite score arc
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color(hex: "#1a1f2d"), lineWidth: 6)
                        .rotationEffect(.degrees(135))

                    Circle()
                        .trim(from: 0, to: 0.75 * Double(store.compositeScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(135))

                    VStack(spacing: 0) {
                        Text("\(store.compositeScore)")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(scoreColor)
                        Text(scoreLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "#555566"))
                    }
                }
                .frame(width: 80, height: 80)
                .padding(.top, 4)

                Divider().background(Color(hex: "#1a1f2d"))

                statRow("SRI", value: String(format: "%.0f%%", store.sri))
                statRow("Acrophase", value: formatHour(store.acrophase))
                statRow("Duration", value: String(format: "%.1fh", store.sleepDuration))
            }
            .padding(.horizontal, 8)
        }
        .background(Color(hex: "#0c0e14"))
        .navigationTitle("Stats")
    }

    private var scoreColor: Color {
        switch store.compositeScore {
        case 80...: return Color(hex: "#5bffa8")
        case 60...: return Color(hex: "#f5c842")
        default:    return Color(hex: "#e05252")
        }
    }

    private var scoreLabel: String {
        switch store.compositeScore {
        case 80...: return "Excelente"
        case 60...: return "Bueno"
        case 40...: return "Moderado"
        default:    return "Atención"
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#555566"))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "#c8cdd8"))
        }
    }

    private func formatHour(_ h: Double) -> String {
        let h24 = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
    }
}
