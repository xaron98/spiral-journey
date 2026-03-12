import SwiftUI

/// Root view for the Watch app.
/// Uses a standard tab view so the Digital Crown is NOT consumed by page-swiping.
struct WatchContentView: View {

    @Environment(WatchStore.self) private var store
    @State private var selectedTab = 0

    private var colorScheme: ColorScheme {
        store.appearance == "light" ? .light : .dark
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchSpiralView()
                .tag(0)
            WatchStatsView()
                .tag(1)
            WatchDayView()
                .tag(2)
            WatchEventLogView()
                .tag(3)
        }
        .environment(\.colorScheme, colorScheme)
        // Do NOT use .page style — that steals the Digital Crown.
        // Standard tab bar style leaves the Crown free for digitalCrownRotation.
        .task {
            // Register callbacks BEFORE loadData so updates that arrive
            // during or immediately after WCSession activation are not missed.
            WatchConnectivityManager.shared.onContextReceived = { context in
                store.updateFromContext(context)
            }
            // Re-read receivedApplicationContext once activation completes.
            // loadData() may run before the session is active and see an empty dict.
            WatchConnectivityManager.shared.onSessionActivated = {
                store.loadFromReceivedContext()
            }
            await store.loadData()
        }
    }
}
