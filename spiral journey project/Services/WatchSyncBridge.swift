import Foundation
import SwiftData
import SpiralKit

/// Syncs SDSleepEpisode data from SwiftData to the shared App Group
/// UserDefaults so the Watch app can read episodes without a live
/// WatchConnectivity session.
///
/// Since SwiftData does not expose a `ModelContext.didSave` notification,
/// the bridge exposes a `syncEpisodes(context:)` method that callers
/// invoke explicitly after any save that modifies episodes.
@MainActor
final class WatchSyncBridge {

    private let appGroupID: String

    init(appGroupID: String) {
        self.appGroupID = appGroupID
    }

    /// Fetch all SDSleepEpisode records from SwiftData, convert to
    /// [SleepEpisode], JSON-encode, and write to shared UserDefaults.
    ///
    /// Call after any SwiftData save that modifies episodes.
    func syncEpisodes(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<SDSleepEpisode>(
                sortBy: [SortDescriptor(\.start)]
            )
            let episodes = try context.fetch(descriptor)
            let spiralKitEpisodes = episodes.map { $0.toSleepEpisode() }

            guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
            let data = try JSONEncoder().encode(spiralKitEpisodes)
            defaults.set(data, forKey: "episodes")
        } catch {
            print("[WatchSyncBridge] Failed: \(error)")
        }
    }
}
