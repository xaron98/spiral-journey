import SwiftUI
import SpiralKit

/// Suspense-like wrapper for heavy mode views inside the tri-modal pager.
///
/// Renders ONLY the `SpiralLoaderView` while `isActive` is fresh, then
/// swaps in the real content after a short delay. The previous approach
/// of always building `content()` behind the loader with opacity(0) made
/// SwiftUI block the main thread in the same frame where the loader
/// needed to paint — so the user never saw the loader animate.
///
/// Usage:
/// ```swift
/// var body: some View {
///     LazyModeView(isActive: isActive) {
///         activeBody
///     }
/// }
/// ```
struct LazyModeView<Content: View>: View {

    let isActive: Bool
    var delay: Duration = .milliseconds(900)
    var loaderColor: Color = SpiralColors.accent
    @ViewBuilder let content: () -> Content

    @State private var contentReady = false

    var body: some View {
        ZStack {
            // Solid background so nothing from the previous page leaks
            // through during the pager's swipe transition.
            SpiralColors.bg.ignoresSafeArea()

            if isActive {
                if contentReady {
                    content()
                        .transition(.opacity)
                } else {
                    SpiralLoaderView(color: loaderColor)
                        .transition(.opacity)
                }
            }
        }
        .task(id: isActive) {
            if isActive {
                contentReady = false
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    contentReady = true
                }
            } else {
                contentReady = false
            }
        }
    }
}
