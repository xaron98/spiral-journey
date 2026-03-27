import SwiftUI

/// Root view for the Watch app.
/// Uses a standard tab view so the Digital Crown is NOT consumed by page-swiping.
struct WatchContentView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
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
            WatchNeuroSpiralCard()
                .tag(4)
        }
        .tabViewStyle(.page)
        .environment(\.colorScheme, colorScheme)
        // .page uses horizontal swipe for tab navigation, leaving the
        // Digital Crown free for digitalCrownRotation in WatchSpiralView.
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Pull fresh sleep from the Watch's own HealthKit — works without iPhone.
                Task { await store.refreshFromHealthKit() }
                // Also ask iPhone for updated data if reachable.
                WatchConnectivityManager.shared.requestDataFromPhone()
            }
        }
    }
}
