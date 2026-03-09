import SwiftUI

struct ContentView: View {
    @Environment(\.languageBundle) private var bundle
    @Environment(SpiralStore.self) private var store
    @State private var selectedTab: AppTab = .spiral

    var body: some View {
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
