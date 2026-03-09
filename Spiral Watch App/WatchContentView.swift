import SwiftUI

/// Root view for the Watch app — tab-style pager.
struct WatchContentView: View {

    @Environment(WatchStore.self) private var store

    var body: some View {
        TabView {
            WatchSpiralView()
            WatchStatsView()
            WatchDayView()
            WatchEventLogView()
        }
        .tabViewStyle(.page)
        .onAppear {
            WatchConnectivityManager.shared.onContextReceived = { context in
                store.updateFromContext(context)
            }
        }
    }
}
