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
    let nowTurns: Double
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
            numDays: 7,
            nowTurns: 0
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

    // Re-index last 7 to days 0-6, re-base timestamps to start from 0
    let last7 = Array(records.suffix(7))
    let baseTimestamp = last7.first?.phases.first?.timestamp ?? 0
    let widgetRecords: [SleepRecord] = last7.enumerated().map { idx, r in
        var copy = r
        copy.day = idx
        copy.phases = r.phases.map { p in
            PhaseInterval(hour: p.hour, phase: p.phase, timestamp: p.timestamp - baseTimestamp)
        }
        return copy
    }

    // "Now" in re-based widget coordinates
    let period = snapshot.period ?? 24.0
    let nowAbsoluteHour = Date.now.timeIntervalSince(snapshot.startDate) / 3600
    let nowRebased = nowAbsoluteHour - baseTimestamp
    let nowTurns = nowRebased / period

    return SpiralEntry(
        date: .now,
        records: widgetRecords,
        spiralType: snapshot.spiralType ?? .logarithmic,
        period: period,
        depthScale: snapshot.depthScale ?? 1.5,
        numDays: min(n, 7),
        nowTurns: nowTurns
    )
}

// MARK: - Timeline Provider

struct SpiralTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpiralEntry {
        SpiralEntry(date: .now, records: [], spiralType: .logarithmic, period: 24.0, depthScale: 1.5, numDays: 7, nowTurns: 0)
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
