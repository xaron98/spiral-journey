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
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "widget.spiral.name", defaultValue: "Spiral"))
        .description(String(localized: "widget.spiral.description", defaultValue: "Your sleep spiral."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
