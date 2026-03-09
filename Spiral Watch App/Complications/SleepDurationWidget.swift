import WidgetKit
import SwiftUI

/// .accessoryRectangular showing sleep duration and SRI.
struct SleepDurationWidget: Widget {
    let kind = "SleepDuration"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpiralTimelineProvider()) { entry in
            SleepDurationView(entry: entry)
        }
        .configurationDisplayName("Sleep Duration")
        .description("Average sleep duration and regularity index.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SleepDurationView: View {
    let entry: SpiralWidgetEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6e3fa0"))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1fh sleep", entry.sleepDuration))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#c8cdd8"))
                Text(String(format: "SRI %.0f%%", entry.sri))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#555566"))
            }
        }
    }
}
