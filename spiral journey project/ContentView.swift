import SwiftUI

struct ContentView: View {
    @Environment(\.languageBundle) private var bundle
    @Environment(SpiralStore.self) private var store
    @State private var selectedTab: AppTab = .spiral
    @State private var onboardingFrames = OnboardingFrames()

    var body: some View {
        @Bindable var store = store

        ZStack(alignment: .center) {
            // ── Main app ─────────────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                SpiralTab(selectedTab: $selectedTab)
                    .tabItem {
                        Label(AppTab.spiral.label(bundle), systemImage: AppTab.spiral.icon)
                    }
                    .tag(AppTab.spiral)

                AnalysisTab()
                    .tabItem {
                        Label(AppTab.trends.label(bundle), systemImage: AppTab.trends.icon)
                    }
                    .tag(AppTab.trends)

                CoachTab()
                    .tabItem {
                        Label(AppTab.coach.label(bundle), systemImage: AppTab.coach.icon)
                    }
                    .tag(AppTab.coach)

                SettingsTab()
                    .tabItem {
                        Label(AppTab.settings.label(bundle), systemImage: AppTab.settings.icon)
                    }
                    .tag(AppTab.settings)
            }
            .tint(SpiralColors.accent)
            .preferredColorScheme(store.appearance.colorScheme)
            .onPreferenceChange(OnboardingFramesKey.self) { frames in
                onboardingFrames = frames
            }
            // Track the tab bar frame via a background GeometryReader on the full TabView
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: OnboardingFramesKey.self,
                        value: {
                            var f = OnboardingFrames()
                            let globalFrame = geo.frame(in: .global)
                            #if os(iOS)
                            let isPad = UIDevice.current.userInterfaceIdiom == .pad
                            #else
                            let isPad = false
                            #endif
                            if isPad {
                                // On iPad, TabView renders tabs at the top
                                let tabH: CGFloat = 70
                                f.tabBar = CGRect(
                                    x: globalFrame.minX,
                                    y: globalFrame.minY,
                                    width: globalFrame.width,
                                    height: tabH
                                )
                            } else {
                                // Tab bar: 49pt above bottom safe area, in global coordinates
                                let tabH: CGFloat = 49 + geo.safeAreaInsets.bottom
                                f.tabBar = CGRect(
                                    x: globalFrame.minX,
                                    y: globalFrame.maxY - tabH,
                                    width: globalFrame.width,
                                    height: tabH
                                )
                            }
                            return f
                        }()
                    )
                }
            )

            // ── Tutorial overlay — sits above TabView, below WelcomeScreen ──
            if store.hasShownWelcome && !store.hasCompletedOnboarding {
                OnboardingOverlayView(frames: onboardingFrames)
                    .transition(.opacity)
                    .zIndex(5)
            }

            // ── Welcome screen — shown before everything else ─────────────
            if !store.hasShownWelcome {
                WelcomeScreenView {
                    // On Continue: switch to Spiral tab, fade out welcome, then show tutorial
                    selectedTab = .spiral
                    store.hasShownWelcome = true
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.hasShownWelcome)
        .animation(.easeInOut(duration: 0.35), value: store.hasCompletedOnboarding)
        // When onboarding resets (e.g. Reset All Data), jump back to Spiral tab
        .onChange(of: store.hasShownWelcome) { _, newVal in
            if !newVal { selectedTab = .spiral }
        }
    }
}

// MARK: - Tab enum

enum AppTab: CaseIterable {
    case spiral, trends, coach, settings

    func label(_ bundle: Bundle) -> String {
        switch self {
        case .spiral:   return String(localized: "tab.spiral",   bundle: bundle)
        case .trends:   return String(localized: "tab.trends",   bundle: bundle)
        case .coach:    return String(localized: "tab.coach",    bundle: bundle)
        case .settings: return String(localized: "tab.settings", bundle: bundle)
        }
    }

    var icon: String {
        switch self {
        case .spiral:   return "moon.stars.fill"
        case .trends:   return "chart.line.uptrend.xyaxis"
        case .coach:    return "lightbulb.min.fill"
        case .settings: return "gear"
        }
    }
}

#Preview {
    ContentView()
        .environment(SpiralStore())
        .environment(HealthKitManager())
        .preferredColorScheme(.dark)
}
