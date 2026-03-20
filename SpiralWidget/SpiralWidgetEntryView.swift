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
                spiralType: entry.spiralType,
                period: entry.period,
                depthScale: entry.depthScale,
                numDays: entry.numDays,
                showHourLabels: family != .systemSmall
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(ContainerRelativeShape())
        }
        .ignoresSafeArea()
    }
}
