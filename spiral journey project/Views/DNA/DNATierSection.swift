import SwiftUI
import SpiralKit

/// Tier indicator at the bottom of the DNA insights view.
struct DNATierSection: View {

    let profile: SleepDNAProfile

    private var tierLabel: String {
        switch profile.tier {
        case .basic:        return "Basico"
        case .intermediate: return "Intermedio"
        case .full:         return "Completo"
        }
    }

    private var tierIcon: String {
        switch profile.tier {
        case .basic:        return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .full:         return "3.circle.fill"
        }
    }

    private var tierColor: Color {
        switch profile.tier {
        case .basic:        return SpiralColors.subtle
        case .intermediate: return SpiralColors.accent
        case .full:         return SpiralColors.good
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tierIcon)
                .font(.system(size: 16))
                .foregroundStyle(tierColor)

            Text("Nivel de analisis: \(tierLabel)")
                .font(.system(size: 13))
                .foregroundStyle(SpiralColors.muted)

            Spacer()

            Text("\(profile.dataWeeks) semanas de datos")
                .font(.system(size: 12))
                .foregroundStyle(SpiralColors.subtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpiralColors.surface.opacity(0.6))
        )
    }
}
