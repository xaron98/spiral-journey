import WidgetKit
import SwiftUI

/// Widget showing circadian state + tonight's sleep prediction.
struct StateWidget: Widget {
    let kind = "StateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StateTimelineProvider()) { entry in
            StateWidgetEntryView(entry: entry)
                .containerBackground(Color(hex: "0c0e14"), for: .widget)
        }
        .configurationDisplayName("Sleep Status")
        .description("Circadian state and tonight's prediction.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
