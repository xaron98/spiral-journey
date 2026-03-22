import WidgetKit
import SwiftUI

@main
struct SpiralWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpiralWidget()
        StateWidget()
    }
}

struct SpiralWidget: Widget {
    let kind = "SpiralWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpiralTimelineProvider()) { entry in
            SpiralWidgetEntryView(entry: entry)
                .containerBackground(Color(hex: "0c0e14"), for: .widget)
        }
        .configurationDisplayName("Spiral")
        .description("Your sleep spiral.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
