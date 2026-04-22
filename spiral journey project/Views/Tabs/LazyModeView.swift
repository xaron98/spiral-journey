import SwiftUI
import SpiralKit

/// Suspense-like wrapper for heavy mode views inside the tri-modal pager.
///
/// Shows a `SpiralLoaderView` on top of a solid background while the real
/// content warms up, then fades the content in. Pattern:
///
/// ```swift
/// var body: some View {
///     LazyModeView(isActive: isActive) {
///         activeBody
///     }
/// }
/// ```
///
/// - `isActive`: true when this mode is the one currently visible in the
///   pager. Content is only rendered (and the loader timer only armed)
///   while active — matches the lazy-body optimization in each mode.
/// - `delay`: how long the loader stays visible before fading the real
///   content in. Long enough that the SpiralLoaderView completes ~1
///   breathe cycle so the user sees it animate.
struct LazyModeView<Content: View>: View {

    let isActive: Bool
    var delay: Duration = .milliseconds(900)
    var loaderColor: Color = SpiralColors.accent
    @ViewBuilder let content: () -> Content

    @State private var contentReady = false

    var body: some View {
        ZStack {
            // Solid background so the loader is always visible — even during
            // the TabView(.page) swipe transition, which can otherwise leak
            // the previous mode's pixels underneath.
            SpiralColors.bg.ignoresSafeArea()

            if isActive {
                // Heavy content is always built when active; we just hide
                // it behind the loader until primed. Important: no ancestor
                // .animation(...) modifier on this ZStack — it would flatten
                // the loader's internal TimelineView progression.
                content()
                    .opacity(contentReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.28), value: contentReady)

                if !contentReady {
                    SpiralLoaderView(color: loaderColor)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
            }
        }
        .task(id: isActive) {
            if isActive {
                contentReady = false
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                contentReady = true
            } else {
                contentReady = false
            }
        }
    }
}
