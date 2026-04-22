import SwiftUI
import SpiralKit

/// Yellow-accent card (or green for positive variant) that surfaces a
/// single "what matters this week" finding. Consumed from a
/// `WeeklyInsight` produced by `WeeklyInsightEngine`.
///
/// Named `WeeklyInsightCard` (not just `InsightCard`) to avoid
/// colliding with an unrelated `InsightCard` view used elsewhere in
/// the Spiral tab for pattern insights.
struct WeeklyInsightCard: View {
    let insight: WeeklyInsight
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 0) {
            // 3pt accent rail on the leading edge.
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized(insight.kickerKey))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(accentColor)
                Text(formatted(insight.headlineKey, args: insight.headlineArgs))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)
                    .lineSpacing(2)
                if let support = insight.supportingKey {
                    Text(formatted(support, args: insight.supportingArgs))
                        .font(.system(size: 12))
                        .foregroundStyle(SpiralColors.subtle)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SpiralColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpiralColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accentColor: Color {
        insight.kind == .goodStreak ? SpiralColors.good : SpiralColors.moderate
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    private func formatted(_ key: String, args: [String]) -> String {
        let template = localized(key)
        guard !args.isEmpty else { return template }
        // %@ substitution with CVarArg variadic. Cast each String to
        // CVarArg since %@ expects Obj-C NSObject on Swift/Darwin.
        let cvarargs: [CVarArg] = args.map { $0 as CVarArg }
        return String(format: template, arguments: cvarargs)
    }
}
