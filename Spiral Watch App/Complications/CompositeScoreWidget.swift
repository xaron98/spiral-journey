import WidgetKit
import SwiftUI

/// .accessoryCircular gauge showing the composite circadian score.
struct CompositeScoreWidget: Widget {
    let kind = "CompositeScore"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpiralTimelineProvider()) { entry in
            CompositeScoreView(entry: entry)
        }
        .configurationDisplayName("Spiral Score")
        .description("Composite circadian rhythm score.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CompositeScoreView: View {
    let entry: SpiralWidgetEntry

    var body: some View {
        Gauge(value: Double(entry.compositeScore), in: 0...100) {
            Image(systemName: "moon.stars.fill")
        } currentValueLabel: {
            Text("\(entry.compositeScore)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(scoreColor)
    }

    private var scoreColor: Color {
        switch entry.compositeScore {
        case 80...: return Color(hex: "#5bffa8")
        case 60...: return Color(hex: "#f5c842")
        default:    return Color(hex: "#e05252")
        }
    }
}
