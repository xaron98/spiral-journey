import SwiftUI

/// Root view for the Watch app.
/// Uses a standard tab view so the Digital Crown is NOT consumed by page-swiping.
struct WatchContentView: View {

    @Environment(WatchStore.self) private var store
    @State private var selectedTab = 0

    private var colorScheme: ColorScheme? {
        switch store.appearance {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil
        }
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
        // Do NOT use .page style — that steals the Digital Crown.
        // Standard tab bar style leaves the Crown free for digitalCrownRotation.
        .preferredColorScheme(colorScheme)
        .task {
            await store.loadData()
            WatchConnectivityManager.shared.onContextReceived = { context in
                store.updateFromContext(context)
            }
        }
    }
}
