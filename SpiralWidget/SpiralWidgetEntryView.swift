import SwiftUI
import WidgetKit
import SpiralKit

struct SpiralWidgetEntryView: View {
    let entry: SpiralEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { geo in
            WidgetSpiralCanvas(
                records: entry.records,
                spiralType: .archimedean,
                period: entry.period,
                numDays: entry.numDays,
                showHourLabels: family != .systemSmall
            )
            .scaleEffect(0.9)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
