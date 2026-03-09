import Foundation
import WatchConnectivity
import SpiralKit

/// Handles WatchConnectivity session on the watchOS side.
/// Receives analysis context from iPhone, sends logged events back.
@MainActor
final class WatchConnectivityManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchConnectivityManager()

    private var session: WCSession?
    var onContextReceived: (([String: Any]) -> Void)?

    override private init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Send event to iPhone

    func sendEvent(_ event: CircadianEvent) {
        guard let session = session, session.isReachable,
              let data = try? JSONEncoder().encode(event) else { return }
        session.sendMessage(["newEvent": data], replyHandler: nil, errorHandler: nil)
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
