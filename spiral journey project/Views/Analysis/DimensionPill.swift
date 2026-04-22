import SwiftUI
import SpiralKit

/// Compact horizontal pill for one of the three weekly dimensions
/// (Consistency / Drift / Duration). Used in a 3-pill HStack replacing
/// the previous full-width trend cards.
struct DimensionPill: View {
    /// ALL-CAPS monospaced label, e.g. "CONSISTENCIA".
    let label: String
    /// Main numeric value, e.g. "36" or "-1.4h".
    let value: String
    /// Optional trailing unit, e.g. "/100".
    let unit: String?
    /// Color tint of the value (good / moderate / poor / muted).
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SpiralColors.subtle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpiralColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SpiralColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
