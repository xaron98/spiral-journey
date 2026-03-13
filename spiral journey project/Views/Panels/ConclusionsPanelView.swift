import SwiftUI
import SpiralKit

/// Full-screen conclusions report sheet (kept for backwards compatibility if needed).
/// The main Analysis tab now hosts this content inline.
struct ConclusionsPanelView: View {

    let analysis: AnalysisResult
    @Binding var isPresented: Bool
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScoreGaugeView(
                        score: analysis.composite,
                        label: analysis.label,
                        hexColor: analysis.hexColor
                    )
                    .frame(width: 160, height: 160)
                    .padding(.top, 8)

                    if !analysis.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PanelTitle(title: String(localized: "conclusions.categories.title", bundle: bundle))
                            ForEach(analysis.categories) { cat in CategoryRow(category: cat, bundle: bundle) }
                        }
                        .panelStyle()
                    }

                    let trends = analysis.trends
                    if !trends.improving.isEmpty || !trends.deteriorating.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PanelTitle(title: String(localized: "conclusions.trends.title", bundle: bundle))
                            ForEach(trends.improving)     { t in trendRow(t, color: SpiralColors.good,  arrow: "arrow.up") }
                            ForEach(trends.deteriorating) { t in trendRow(t, color: SpiralColors.poor,  arrow: "arrow.down") }
                            ForEach(trends.stable)        { t in trendRow(t, color: SpiralColors.muted, arrow: "minus") }
                        }
                        .panelStyle()
                    }

                    if !analysis.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            PanelTitle(title: String(localized: "conclusions.recommendations.title", bundle: bundle))
                            ForEach(analysis.recommendations) { rec in RecommendationRow(rec: rec, bundle: bundle) }
                        }
                        .panelStyle()
                    }
                }
                .padding()
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle("Spiral Journey")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(String(localized: "conclusions.done", bundle: bundle)) { isPresented = false }
                        .foregroundStyle(SpiralColors.accent)
                }
            }
        }
    }

    private func loc(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    private func localizedTrendLabel(_ t: TrendItem) -> String {
        if let key = t.labelKey { return loc("trend.\(key.rawValue)") }
        return t.label
    }

    private func localizedTrendDetail(_ t: TrendItem) -> String {
        guard let key = t.detailKey else { return t.detail }
        let fmt = loc("trend.detail.\(key.rawValue)")
        if t.detailArgs.isEmpty { return fmt }
        switch t.detailArgs.count {
        case 1: return String(format: fmt, t.detailArgs[0])
        case 2: return String(format: fmt, t.detailArgs[0], t.detailArgs[1])
        default: return fmt
        }
    }

    private func trendRow(_ t: TrendItem, color: Color, arrow: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: arrow).font(.system(size: 10, weight: .bold)).foregroundStyle(color).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(localizedTrendLabel(t)).font(.system(size: 11, weight: .medium)).foregroundStyle(SpiralColors.text)
                Text(localizedTrendDetail(t)).font(.system(size: 9)).foregroundStyle(SpiralColors.muted)
            }
        }
    }
}
