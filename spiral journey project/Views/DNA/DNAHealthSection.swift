import SwiftUI
import SpiralKit

/// "Tu salud circadiana" — health alerts from markers; green checkmark when all clear.
struct DNAHealthSection: View {

    let profile: SleepDNAProfile

    private var markers: HealthMarkers { profile.healthMarkers }
    private var relevantAlerts: [HealthAlert] { markers.alerts }
    private var allGood: Bool { relevantAlerts.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "heart.text.clipboard")
                    .foregroundStyle(SpiralColors.accent)
                Text("Tu salud circadiana")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            if allGood {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SpiralColors.good)
                    Text("Estable")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SpiralColors.good)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(relevantAlerts) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SpiralColors.surface)
        )
    }

    // MARK: - Alert Row

    @ViewBuilder
    private func alertRow(_ alert: HealthAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alertIcon(alert.severity))
                .font(.system(size: 14))
                .foregroundStyle(alertColor(alert.severity))
                .frame(width: 20)

            Text(alert.message)
                .font(.system(size: 13))
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func alertIcon(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .urgent:  return "exclamationmark.octagon.fill"
        }
    }

    private func alertColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .info:    return SpiralColors.accent
        case .warning: return SpiralColors.awakeSleep
        case .urgent:  return SpiralColors.poor
        }
    }
}
