import Foundation
import WatchConnectivity
import SpiralKit

/// Handles WatchConnectivity on the watchOS side.
/// Receives analysis data from iPhone, sends logged events back.
@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityManager()
    var onContextReceived: (([String: Any]) -> Void)?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Send to iPhone

    func sendEvent(_ event: CircadianEvent) {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(event) else { return }
        WCSession.default.sendMessage(["newEvent": data], replyHandler: nil, errorHandler: nil)
    }

    func sendEpisode(_ episode: SleepEpisode) {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(episode) else { return }
        WCSession.default.sendMessage(["newEpisode": data], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.onContextReceived?(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.onContextReceived?(message)
        }
    }
}
