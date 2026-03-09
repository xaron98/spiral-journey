import Foundation
import Observation
import SpiralKit

/// Lightweight observable store for the Watch app.
/// Receives full analysis data from the iOS app via WatchConnectivity,
/// and also queries HealthKit directly for recent sleep data.
@MainActor
@Observable
final class WatchStore {

    var records: [SleepRecord] = []
    var events: [CircadianEvent] = []
    var analysis: AnalysisResult = AnalysisResult.empty
    var isLoading = false

    // Computed shortcuts
    var compositeScore: Int { analysis.composite }
    var sri: Double { analysis.stats.sri }
    var acrophase: Double { analysis.stats.meanAcrophase }
    var sleepDuration: Double { analysis.stats.meanSleepDuration }

    // Last 7 records for compact spiral
    var recentRecords: [SleepRecord] {
        Array(records.suffix(7))
    }

    /// Called by WatchConnectivityManager when new context arrives from iPhone.
    func updateFromContext(_ context: [String: Any]) {
        guard let data = context["analysisJSON"] as? Data,
              let decoded = try? JSONDecoder().decode(AnalysisResult.self, from: data) else { return }
        analysis = decoded

        if let recordsData = context["recordsJSON"] as? Data,
           let decodedRecords = try? JSONDecoder().decode([SleepRecord].self, from: recordsData) {
            records = decodedRecords
        }
        if let eventsData = context["eventsJSON"] as? Data,
           let decodedEvents = try? JSONDecoder().decode([CircadianEvent].self, from: eventsData) {
            events = decodedEvents
        }
    }

    /// Append an event logged on the watch and request iPhone sync.
    func logEvent(_ event: CircadianEvent) {
        events.append(event)
        WatchConnectivityManager.shared.sendEvent(event)
    }
}
