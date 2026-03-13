import WidgetKit
import SpiralKit
import Foundation

// MARK: - Timeline Entry

struct SpiralEntry: TimelineEntry {
    let date: Date
    let records: [SleepRecord]
    let spiralType: SpiralType
    let period: Double
    let depthScale: Double
    let numDays: Int
}

// MARK: - Shared Data Loader

private struct StoredSnapshot: Codable {
    var sleepEpisodes: [SleepEpisode]
    var startDate: Date
    var numDays: Int
    var spiralType: SpiralType?
    var period: Double?
    var depthScale: Double?
}

private func loadEntry() -> SpiralEntry {
    let defaults = UserDefaults(suiteName: "group.xaron.spiral-journey-project")
    guard
        let data = defaults?.data(forKey: "spiral-journey-store"),
        let snapshot = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
        !snapshot.sleepEpisodes.isEmpty
    else {
        return SpiralEntry(
            date: .now,
            records: [],
            spiralType: .logarithmic,
            period: 24.0,
            depthScale: 1.5,
            numDays: 7
        )
    }

    let lastEnd = snapshot.sleepEpisodes.map(\.end).max() ?? 0
    let neededDays = min(Int(ceil(lastEnd / 24.0)), snapshot.numDays)
    let n = max(neededDays, 1)
    let records = ManualDataConverter.convert(
        episodes: snapshot.sleepEpisodes,
        numDays: n,
        startDate: snapshot.startDate
    )

    return SpiralEntry(
        date: .now,
        records: records,
        spiralType: snapshot.spiralType ?? .logarithmic,
        period: snapshot.period ?? 24.0,
        depthScale: snapshot.depthScale ?? 1.5,
        numDays: n
    )
}

// MARK: - Timeline Provider

struct SpiralTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpiralEntry {
        SpiralEntry(date: .now, records: [], spiralType: .logarithmic, period: 24.0, depthScale: 1.5, numDays: 7)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpiralEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpiralEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes (app also triggers an explicit reload on save)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
