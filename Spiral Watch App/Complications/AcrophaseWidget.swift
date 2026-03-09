import WidgetKit
import SwiftUI

/// .accessoryInline showing today's acrophase (activity peak time).
struct AcrophaseWidget: Widget {
    let kind = "Acrophase"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpiralTimelineProvider()) { entry in
            AcrophaseView(entry: entry)
        }
        .configurationDisplayName("Acrophase")
        .description("Circadian activity peak time.")
        .supportedFamilies([.accessoryInline])
    }
}

struct AcrophaseView: View {
    let entry: SpiralWidgetEntry

    var body: some View {
        Label(
            "Peak \(formatHour(entry.acrophase))",
            systemImage: "waveform.path.ecg"
        )
    }

    private func formatHour(_ h: Double) -> String {
        let h24 = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
    }
}

// MARK: - Shared Timeline Provider

/// Simple timeline provider used by all Spiral Journey complications.
struct SpiralTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> SpiralWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SpiralWidgetEntry) -> Void) {
        completion(WidgetDataKey.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpiralWidgetEntry>) -> Void) {
        let entry = WidgetDataKey.load()
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
