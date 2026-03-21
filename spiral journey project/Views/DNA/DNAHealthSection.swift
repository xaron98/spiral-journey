import SwiftUI
import SpiralKit

/// "Tu salud circadiana" — health alerts from markers; green checkmark when all clear.
struct DNAHealthSection: View {

    let profile: SleepDNAProfile

    @Environment(\.languageBundle) private var bundle

    private var markers: HealthMarkers { profile.healthMarkers }
    private var relevantAlerts: [HealthAlert] { markers.alerts }
    private var allGood: Bool { relevantAlerts.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "heart.text.clipboard")
                    .foregroundStyle(SpiralColors.accent)
                Text(loc("dna.health.header"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            if allGood {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(SpiralColors.good)
                    Text(loc("dna.health.stable"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SpiralColors.good)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(relevantAlerts) { alert in
                        alertRow(alert)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Alert Row

    @ViewBuilder
    private func alertRow(_ alert: HealthAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alertIcon(alert.severity))
                .font(.body)
                .foregroundStyle(alertColor(alert.severity))
                .frame(width: 20)

            Text(localizedMessage(for: alert))
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Map alert type to localized message instead of using hardcoded English from the engine.
    private func localizedMessage(for alert: HealthAlert) -> String {
        switch alert.type {
        case .circadianAnarchy:
            return loc("dna.health.alert.anarchy")
        case .highFragmentation:
            return loc("dna.health.alert.fragmentation")
        case .severeDrift:
            return loc("dna.health.alert.drift")
        case .highDesynchrony:
            return loc("dna.health.alert.desync")
        case .remDriftAbnormal:
            return loc("dna.health.alert.rem")
        case .novelPattern:
            return loc("dna.health.alert.novel")
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

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
