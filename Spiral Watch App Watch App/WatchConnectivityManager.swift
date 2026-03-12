import Foundation
import WatchConnectivity
import SpiralKit

/// Handles WatchConnectivity on the watchOS side.
/// Receives analysis data from iPhone, sends logged events back.
@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityManager()
    var onContextReceived: (([String: Any]) -> Void)?
    /// Called after WCSession activation completes so the store can re-read
    /// receivedApplicationContext (which is only populated after activation).
    var onSessionActivated: (() -> Void)?

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

    // MARK: - Request data from iPhone

    /// Ask the iPhone to push a fresh data context. Call this on launch when
    /// receivedApplicationContext is empty (e.g. first install or after reinstall).
    func requestDataFromPhone() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["requestData": true], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            // Always notify the store so it can re-read receivedApplicationContext.
            // The context dict is only populated after activation completes,
            // so loadData() may have seen an empty dict if it ran too early.
            self.onSessionActivated?()
            // Also proactively request fresh data if iPhone is reachable right now.
            if session.isReachable {
                self.requestDataFromPhone()
            }
        }
    }

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
