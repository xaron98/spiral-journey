import Foundation
import MultipeerConnectivity
import Observation
import SpiralKit

/// Manages Multipeer Connectivity sessions for ephemeral peer sleep comparison.
///
/// Privacy-first: only aggregated `ComparisonPayload` is transmitted — no raw records,
/// no health data, no events. Data exists only while connected; cleared on disconnect.
@MainActor @Observable
final class PeerComparisonManager: NSObject {

    // MARK: - Types

    enum State {
        case idle, searching, connected, disconnected
    }

    // MARK: - Observable Properties

    var state: State = .idle
    var peerAlias: String?
    var peerPayload: ComparisonPayload?

    // MARK: - Private

    private static let serviceType = "spiral-compare"

    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var myPeerID: MCPeerID?
    private var myPayload: ComparisonPayload?

    // MARK: - Public API

    /// Begin searching for nearby peers. Creates MC session, starts browsing + advertising.
    /// - Parameters:
    ///   - alias: Display name for this device (shown to peer).
    ///   - myPayload: Pre-built comparison payload to send upon connection.
    func startSearching(alias: String, myPayload: ComparisonPayload) {
        stopSearching()

        self.myPayload = myPayload

        let peerID = MCPeerID(displayName: alias)
        self.myPeerID = peerID

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["alias": alias],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser

        browser.startBrowsingForPeers()
        advertiser.startAdvertisingPeer()

        state = .searching
    }

    /// Stop browsing/advertising and disconnect the session. Clears all peer data.
    func stopSearching() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()

        browser = nil
        advertiser = nil
        session = nil
        myPeerID = nil
        myPayload = nil
        peerAlias = nil
        peerPayload = nil

        state = .idle
    }

    /// End the current session. Sets state to `.disconnected` and clears peer data.
    func disconnect() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()

        browser = nil
        advertiser = nil
        session = nil
        peerAlias = nil
        peerPayload = nil

        state = .disconnected
    }

    // MARK: - Private Helpers

    private func sendPayload(to peer: MCPeerID) {
        guard let session, let payload = myPayload else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            // Best effort — if send fails the peer just won't see our data
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerComparisonManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange newState: MCSessionState) {
        Task { @MainActor in
            switch newState {
            case .connected:
                // Send our payload to the newly connected peer
                sendPayload(to: peerID)
            case .notConnected:
                peerAlias = nil
                peerPayload = nil
                if state == .connected || state == .searching {
                    state = .disconnected
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(ComparisonPayload.self, from: data) else { return }
        Task { @MainActor in
            peerPayload = payload
            peerAlias = payload.alias
            state = .connected
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerComparisonManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Auto-invite — both devices are actively in the comparison screen
        Task { @MainActor in
            guard let session = self.session else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // No action needed — session delegate handles disconnect
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerComparisonManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept — both devices are actively searching
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}
