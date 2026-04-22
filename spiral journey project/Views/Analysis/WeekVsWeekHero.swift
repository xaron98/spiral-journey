import SwiftUI
import SpiralKit

/// Purple-gradient container that wraps the existing WeekComparisonCard
/// as the hero of the Trends tab. The card's internal 3D spirals are
/// untouched; this file only owns the outer chrome.
struct WeekVsWeekHero: View {
    let records: [SleepRecord]
    let spiralType: SpiralType
    let period: Double
    /// Tint of the gradient: purple for the usual case, green when the
    /// caller detected a "good week" (consistency + SRI both ≥ 75).
    var good: Bool = false

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "analysis.hero.kicker", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(kickerColor)

            WeekComparisonCard(
                records: records,
                spiralType: spiralType,
                period: period)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [tintColor.opacity(0.15), SpiralColors.surface.opacity(0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(tintColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var tintColor: Color {
        good ? SpiralColors.good : SpiralColors.accent
    }

    private var kickerColor: Color {
        good ? SpiralColors.good : SpiralColors.accent
    }
}
