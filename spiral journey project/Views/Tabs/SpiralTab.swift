import SwiftUI
import SpiralKit

/// Tri-modal pager container: Torus (0) | Spiral (1) | DNA (2).
///
/// Hosts the contextual header, mode pills selector, and a swipeable
/// pager (TabView on iOS, plain switch on macOS where .page is unavailable).
/// Default selection is the Spiral chronobiograph (center, index 1).
struct SpiralTab: View {
    @Environment(SpiralStore.self) private var store
    @Binding var selectedTab: AppTab
    @State private var selectedMode: Int = 1 // Default: Spiral (center)
    // Hoisted here so the navigationDestination attaches to NavigationStack
    // directly. Inside TabView(.page) the destination would sit in a lazy
    // container and SwiftUI ignores it.
    @State private var showConsistencyDetail = false

    var body: some View {
        NavigationStack {
            GeometryReader { screen in
                VStack(spacing: 0) {
                    // ── Fixed header: contextual text + mode pills ──
                    VStack(spacing: 8) {
                        ModeHeaderView(selectedMode: selectedMode)
                            .padding(.top, screen.safeAreaInsets.top + 8)
                        ModePillsView(selectedMode: $selectedMode)
                    }

                    // ── Pager: three mode views ──
                    #if os(macOS)
                    // macOS has no .page tab view style — switch directly
                    Group {
                        switch selectedMode {
                        case 0:  TorusModeView(isActive: true)
                        case 2:  DNAModeView(isActive: true)
                        default: SpiralModeView(selectedTab: $selectedTab,
                                                isActive: true,
                                                showConsistencyDetail: $showConsistencyDetail)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.18), value: selectedMode)
                    #else
                    TabView(selection: $selectedMode) {
                        TorusModeView(isActive: selectedMode == 0)
                            .tag(0)
                        SpiralModeView(selectedTab: $selectedTab,
                                       isActive: selectedMode == 1,
                                       showConsistencyDetail: $showConsistencyDetail)
                            .tag(1)
                        DNAModeView(isActive: selectedMode == 2)
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    // Short animation so pill taps feel immediate. Longer
                    // durations made the view feel unresponsive because
                    // the old selection kept rendering mid-transition.
                    .animation(.easeInOut(duration: 0.18), value: selectedMode)
                    #endif
                }
                .ignoresSafeArea(edges: .top)
                .background(SpiralColors.bg.ignoresSafeArea())
            }
            .navigationDestination(isPresented: $showConsistencyDetail) {
                if let consistency = store.analysis.consistency {
                    ConsistencyDetailView(consistency: consistency, records: store.records)
                }
            }
        }
    }
}
