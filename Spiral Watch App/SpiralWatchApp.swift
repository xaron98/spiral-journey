import SwiftUI

@main
struct SpiralWatchApp: App {

    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(store)
        }
    }
}
