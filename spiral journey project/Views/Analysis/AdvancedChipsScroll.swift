import SwiftUI
import SpiralKit

/// Horizontal row of chips that replaces the old inline-toggle
/// advanced chart section. Each chip presents its chart as a sheet.
struct AdvancedChipsScroll: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var presented: ChartKind?

    enum ChartKind: String, Identifiable, CaseIterable {
        case cosinor, drift, actogram, prc, hrv, periodogram, timeline, autocorrelation, sectorQuality
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "analysis.advanced.title", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChartKind.allCases) { kind in
                        chip(for: kind)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
        .sheet(item: $presented) { kind in
            sheetBody(for: kind)
        }
    }

    private func chip(for kind: ChartKind) -> some View {
        Button {
            presented = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(for: kind))
                    .font(.system(size: 14))
                    .foregroundStyle(color(for: kind))
                Text(String(localized: String.LocalizationValue(titleKey(for: kind)),
                            bundle: bundle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SpiralColors.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SpiralColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(SpiralColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "analysis.advanced.chip.a11yHint", bundle: bundle))
    }

    @ViewBuilder
    private func sheetBody(for kind: ChartKind) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch kind {
                    case .cosinor:        SlidingCosinorView(records: store.records)
                    case .drift:          DriftChartView(records: store.records)
                    case .actogram:       ActogramView(records: store.records)
                    case .prc:            PRCChartView(events: store.events)
                    case .hrv:            HRVTrendView(hrvData: store.hrvData)
                    case .periodogram:
                        PeriodogramView(
                            periodogramResults: store.analysis.periodogramResults,
                            healthProfiles: store.healthProfiles,
                            recordCount: store.records.count)
                    case .timeline:
                        DiscoveryTimelineView(
                            discoveries: DiscoveryDetector.detect(
                                records: store.records,
                                dnaProfile: store.dnaProfile,
                                consistency: store.analysis.consistency,
                                periodograms: store.analysis.periodogramResults,
                                healthProfiles: store.healthProfiles,
                                events: store.events,
                                startDate: store.startDate))
                    case .autocorrelation: AutocorrelationHeatmapView(records: store.records)
                    case .sectorQuality:   SectorQualityHeatmapView(records: store.records)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(String(localized: String.LocalizationValue(titleKey(for: kind)),
                                    bundle: bundle))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", bundle: bundle)) {
                        presented = nil
                    }
                }
            }
        }
    }

    private func icon(for kind: ChartKind) -> String {
        switch kind {
        case .cosinor:         return "waveform.path"
        case .drift:           return "chart.line.downtrend.xyaxis"
        case .actogram:        return "calendar"
        case .prc:             return "chart.dots.scatter"
        case .hrv:             return "heart.text.square"
        case .periodogram:     return "chart.bar"
        case .timeline:        return "point.topleft.down.to.point.bottomright.curvepath"
        case .autocorrelation: return "square.grid.4x3.fill"
        case .sectorQuality:   return "circle.grid.2x2"
        }
    }

    private func color(for kind: ChartKind) -> Color {
        // Every chip uses a semantic SpiralColors token so the palette
        // stays coherent with the rest of the app across light/dark.
        switch kind {
        case .cosinor:         return SpiralColors.moderate
        case .drift:           return SpiralColors.accent
        case .actogram:        return SpiralColors.accentDim
        case .prc:             return SpiralColors.good
        case .hrv:             return SpiralColors.poor
        case .periodogram:     return SpiralColors.accent
        case .timeline:        return SpiralColors.subtle
        case .autocorrelation: return SpiralColors.good
        case .sectorQuality:   return SpiralColors.moderate
        }
    }

    private func titleKey(for kind: ChartKind) -> String {
        "analysis.advanced.\(kind.rawValue).title"
    }
}
