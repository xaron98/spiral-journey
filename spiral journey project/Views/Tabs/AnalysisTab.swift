import SwiftUI
import SpiralKit
#if canImport(UIKit)
import UIKit
#endif

/// Trends tab — answers "¿esto es puntual o es patrón?".
struct AnalysisTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @AppStorage("analysis.selectedWeekOffset") private var selectedWeekOffset: Int = 0
    @State private var isGeneratingPDF = false

    var body: some View {
        ZStack {
            SpiralColors.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if store.records.isEmpty {
                        emptyState
                    } else {
                        trendHeader
                        WeekCarousel(
                            availableWeeks: max(1, store.records.count / 7),
                            selectedOffset: $selectedWeekOffset)
                        weekHero
                        if let insight = weeklyInsight {
                            WeeklyInsightCard(insight: insight)
                        }
                        dimensionsRow
                        NightByNightCard(records: displayRecords)
                        AdvancedChipsScroll()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Header

    private var trendHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "analysis.header.weekNumber", bundle: bundle),
                            currentWeekNumber))
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(SpiralColors.subtle)
                Text(String(localized: "analysis.header.thisWeek", bundle: bundle))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(SpiralColors.text)
            }
            Spacer()
            Button {
                generateAndSharePDF()
            } label: {
                if isGeneratingPDF {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(SpiralColors.accent)
                }
            }
            .disabled(isGeneratingPDF)
            .accessibilityLabel(String(localized: "analysis.share.pdf", bundle: bundle))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Hero

    private var weekHero: some View {
        WeekVsWeekHero(
            records: displayRecords,
            spiralType: store.spiralType,
            period: store.period,
            good: isGoodWeek)
    }

    // MARK: - Dimensions row

    private var dimensionsRow: some View {
        // Capture the analysis snapshot once — the property is computed
        // on the @Observable store and walking it three times per body
        // eval (consistency + stats.stdBedtime + stats.meanSleepDuration)
        // adds unnecessary observation churn.
        let analysis = store.analysis
        let c = analysis.consistency
        let drift = analysis.stats.stdBedtime * 60.0   // minutes
        let duration = analysis.stats.meanSleepDuration
        return HStack(spacing: 10) {
            DimensionPill(
                label: String(localized: "analysis.dim.consistency", bundle: bundle),
                value: c.map { "\($0.score)" } ?? "--",
                unit: "/100",
                valueColor: consistencyColor(for: c?.label ?? .insufficient))
            DimensionPill(
                label: String(localized: "analysis.dim.drift", bundle: bundle),
                value: drift > 0 ? String(format: "%dm", Int(drift)) : "--",
                unit: nil,
                valueColor: drift < 45 ? SpiralColors.good
                          : drift < 90 ? SpiralColors.moderate
                          : SpiralColors.poor)
            DimensionPill(
                label: String(localized: "analysis.dim.duration", bundle: bundle),
                value: duration > 0 ? String(format: "%.1fh", duration) : "--",
                unit: nil,
                valueColor: duration >= 7.0 ? SpiralColors.good
                          : duration >= 6.0 ? SpiralColors.moderate
                          : SpiralColors.poor)
        }
    }

    // MARK: - Insight

    private var weeklyInsight: WeeklyInsight? {
        let analysis = store.analysis
        return WeeklyInsightEngine.generate(
            records: displayRecords,
            stats: analysis.stats,
            consistency: analysis.consistency)
    }

    // MARK: - Derived

    private var displayRecords: [SleepRecord] {
        let end = store.records.count - selectedWeekOffset * 7
        let start = max(0, end - 7)
        guard start < end else { return [] }
        return Array(store.records[start..<end])
    }

    private var currentWeekNumber: Int {
        let refDate = displayRecords.last?.date ?? Date()
        return Calendar.current.component(.weekOfYear, from: refDate)
    }

    /// True when the displayed week qualifies for the positive "good
    /// streak" insight. Derives from `weeklyInsight` so the tint of the
    /// hero can never disagree with the card below it — and it respects
    /// `selectedWeekOffset`, unlike reading `store.analysis` directly.
    private var isGoodWeek: Bool {
        weeklyInsight?.kind == .goodStreak
    }

    private func consistencyColor(for label: ConsistencyLabel) -> Color {
        switch label {
        case .veryStable, .stable: return SpiralColors.good
        case .variable:            return SpiralColors.moderate
        case .disorganized:        return SpiralColors.poor
        case .insufficient:        return SpiralColors.muted
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(SpiralColors.muted)
                .padding(.top, 60)
            Text(String(localized: "analysis.empty.title", bundle: bundle))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SpiralColors.text)
            Text(String(localized: "analysis.empty.body", bundle: bundle))
                .font(.system(size: 13))
                .foregroundStyle(SpiralColors.subtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - PDF

    /// Generates the PDF on a background thread, then presents the share sheet.
    ///
    /// `PDFReportGenerator` uses Core Graphics (`CGContext`) instead of
    /// `UIGraphicsPDFRenderer`, so it's fully thread-safe and won't block the UI.
    private func generateAndSharePDF() {
        isGeneratingPDF = true

        // Snapshot data on main actor before dispatching to background.
        let records = store.records
        let analysis = store.analysis
        let consistency = store.analysis.consistency
        let numDays = store.numDays
        let df = DateFormatter()
        df.dateStyle = .medium
        let dateRange = "\(df.string(from: store.startDate)) – \(df.string(from: Date()))"

        let langBundle = bundle

        Task {
            let data: Data = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: PDFReportGenerator.generate(
                        records: records,
                        analysis: analysis,
                        consistency: consistency,
                        dateRange: dateRange,
                        numDays: numDays,
                        bundle: langBundle
                    ))
                }
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpiralJourney_SleepReport.pdf")
            try? data.write(to: url)

            isGeneratingPDF = false
            presentShareSheet(url: url)
        }
    }

    /// Presents UIActivityViewController from the topmost view controller.
    @MainActor
    private func presentShareSheet(url: URL) {
        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 60, width: 0, height: 0)
        }
        topVC.present(activityVC, animated: true)
        #endif
    }
}

// MARK: - Shared sub-views (used here and in ConclusionsPanelView)

struct CategoryRow: View {
    let category: CategoryScore
    var bundle: Bundle = .main

    private var statusColor: Color {
        switch category.status {
        case .good:     return SpiralColors.good
        case .moderate: return SpiralColors.moderate
        case .poor:     return SpiralColors.poor
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var localizedLabel: String {
        if let key = category.labelKey { return loc("category.\(key.rawValue)") }
        return category.label
    }

    private var localizedDetail: String {
        if let key = category.detailKey { return loc("category.detail.\(key.rawValue)") }
        // For "pattern" category, resolve the description via PDF disorder keys.
        if category.id == "pattern" && category.value != "--" {
            let resolved = loc("pdf.disorder.desc.\(category.value)")
            if resolved != "pdf.disorder.desc.\(category.value)" { return resolved }
        }
        return category.detail
    }

    /// For the "pattern" category, value is a disorder id (e.g. "n24swd") —
    /// resolve it to a human-readable localized name via the existing PDF keys.
    private var localizedValue: String {
        if category.id == "pattern" && category.value != "--" {
            let resolved = loc("pdf.disorder.\(category.value)")
            // If the key isn't found, NSLocalizedString returns the key itself.
            if resolved != "pdf.disorder.\(category.value)" { return resolved }
        }
        return category.value
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(SpiralColors.border).frame(width: 48, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor)
                    .frame(width: CGFloat(category.score) / 100 * 48, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(localizedLabel)
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Text(localizedValue)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(statusColor)
                    Text("\(category.score)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.subtle)
                }
                Text(localizedDetail)
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecommendationRow: View {
    let rec: Recommendation
    var bundle: Bundle = .main

    private var priorityColor: Color {
        switch rec.priority {
        case 1:  return SpiralColors.poor
        case 2:  return SpiralColors.moderate
        default: return SpiralColors.accentDim
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var localizedTitle: String {
        if let key = rec.key { return loc("rec.\(key.rawValue).title") }
        return rec.title
    }

    private func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60; let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var localizedText: String {
        guard let key = rec.key else { return rec.text }
        let fmt = loc("rec.\(key.rawValue).text")
        if rec.args.isEmpty { return fmt }
        // Jetlag recs pass minutes — format as hours for display
        if key == .reduceSocialJetlag || key == .minimizeWeekendLag {
            return String(format: fmt, formatJetlag(rec.args[0]))
        }
        switch rec.args.count {
        case 1: return String(format: fmt, rec.args[0])
        case 2: return String(format: fmt, rec.args[0], rec.args[1])
        default: return fmt
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(localizedTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(localizedText)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
