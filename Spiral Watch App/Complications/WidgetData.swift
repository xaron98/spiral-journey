import Foundation
import WidgetKit

/// Shared data model for all Spiral Journey complications.
/// Loaded from App Group UserDefaults so the widget extension can read it.
struct SpiralWidgetEntry: TimelineEntry {
    let date: Date
    let compositeScore: Int
    let sleepDuration: Double   // hours
    let acrophase: Double       // 0-24h
    let sri: Double             // 0-100

    static let placeholder = SpiralWidgetEntry(
        date: Date(),
        compositeScore: 72,
        sleepDuration: 7.5,
        acrophase: 14.8,
        sri: 78
    )
}

/// Key used to share data between the app and widget extension via UserDefaults.
enum WidgetDataKey {
    static let suiteName = "group.sushi.spiral-journey-project"
    static let entryKey  = "spiralWidgetEntry"

    static func save(_ entry: SpiralWidgetEntry) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: entryKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> SpiralWidgetEntry {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: entryKey),
              let entry = try? JSONDecoder().decode(SpiralWidgetEntry.self, from: data) else {
            return .placeholder
        }
        return entry
    }
}

extension SpiralWidgetEntry: Codable {}
