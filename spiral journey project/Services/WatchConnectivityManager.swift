#if os(iOS)
import Foundation
import WatchConnectivity
import SpiralKit

/// Handles WatchConnectivity session on the iOS side.
/// Sends analysis snapshots to the Apple Watch and receives logged events.
@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityManager()
    var onEventReceived: ((CircadianEvent) -> Void)?
    var onEpisodeReceived: ((SleepEpisode) -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Send full analysis context to Watch

    func sendAnalysis(records: [SleepRecord], events: [CircadianEvent], analysis: AnalysisResult,
                      language: String? = nil, appearance: String? = nil) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }

        var context: [String: Any] = [:]

        if let data = try? JSONEncoder().encode(analysis) {
            context["analysisJSON"] = data
        }
        // Only send last 30 records to keep context small
        let recentRecords = Array(records.suffix(30))
        if let data = try? JSONEncoder().encode(recentRecords) {
            context["recordsJSON"] = data
        }
        if let data = try? JSONEncoder().encode(events) {
            context["eventsJSON"] = data
        }
        if let language {
            context["language"] = language
        }
        if let appearance {
            context["appearance"] = appearance
        }

        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - Send settings-only update to Watch

    /// Sends just language and appearance without re-encoding full analysis data.
    /// Call this when the user changes language or appearance in Settings.
    func sendSettings(language: String, appearance: String) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return }
        // Merge into the existing application context so data keys are preserved.
        var context = WCSession.default.applicationContext
        context["language"]   = language
        context["appearance"] = appearance
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        if let data = message["newEvent"] as? Data,
           let event = try? JSONDecoder().decode(CircadianEvent.self, from: data) {
            Task { @MainActor in self.onEventReceived?(event) }
        }
        if let data = message["newEpisode"] as? Data,
           let episode = try? JSONDecoder().decode(SleepEpisode.self, from: data) {
            Task { @MainActor in self.onEpisodeReceived?(episode) }
        }
    }
}
#endif
