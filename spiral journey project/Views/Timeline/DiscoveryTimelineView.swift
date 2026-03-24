import SwiftUI
import SpiralKit

/// Vertical timeline showing automatically detected milestones in the user's sleep journey.
struct DiscoveryTimelineView: View {

    let discoveries: [Discovery]

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTitle(title: String(localized: "discovery.timeline.title", bundle: bundle))

            if discoveries.isEmpty {
                Text(String(localized: "discovery.timeline.empty", bundle: bundle))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(discoveries.reversed().enumerated()), id: \.element.id) { index, discovery in
                    HStack(alignment: .top, spacing: 12) {
                        // Timeline connector
                        VStack(spacing: 0) {
                            Circle()
                                .fill(SpiralColors.accent)
                                .frame(width: 10, height: 10)
                            if index < discoveries.count - 1 {
                                Rectangle()
                                    .fill(SpiralColors.accent.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 10)

                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: discovery.icon)
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.accent)
                                Text(String(localized: String.LocalizationValue(discovery.titleKey), bundle: bundle))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SpiralColors.text)
                            }

                            Text(String(localized: String.LocalizationValue(discovery.detailKey), bundle: bundle))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(discovery.date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(SpiralColors.subtle)
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .glassPanel()
    }
}
