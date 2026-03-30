import SwiftUI
import SpiralKit

/// Linear actogram: one row per day, activity bars colored by sleep/wake state.
struct ActogramView: View {

    let records: [SleepRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: "Actogram")

            Canvas { context, size in
                guard !records.isEmpty else { return }
                let rowH = size.height / Double(records.count)
                let colW = size.width / 24.0

                for record in records {
                    let y = Double(record.day) * rowH

                    // Weekend background
                    if record.isWeekend {
                        let rect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                        context.fill(Rectangle().path(in: rect),
                                     with: .color(SpiralColors.weekend.opacity(0.2)))
                    }

                    // Activity bars
                    for ha in record.hourlyActivity {
                        let x = Double(ha.hour) * colW
                        let barH = ha.activity * rowH * 0.85
                        let barY = y + (rowH - barH)
                        let rect = CGRect(x: x, y: barY, width: colW - 0.5, height: barH)
                        let color = ha.activity < 0.2
                            ? SpiralColors.viridis(0.1)
                            : SpiralColors.viridis(ha.activity)
                        context.fill(Rectangle().path(in: rect), with: .color(color))
                    }

                    // Day separator line
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(SpiralColors.border.opacity(0.4)), lineWidth: 0.4)
                }

                // Hour markers at top
                for h in stride(from: 0, through: 24, by: 6) {
                    let x = Double(h) * colW
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 0))
                    tick.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(tick, with: .color(SpiralColors.border.opacity(0.5)), lineWidth: 0.5)
                }
            }
            .frame(height: min(Double(records.count) * 8, 200))
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Hour labels
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    if h < 24 { Spacer() }
                }
            }
        }
        .glassPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "accessibility.chart.actogram", defaultValue: "Actogram sleep pattern chart"))
    }
}
