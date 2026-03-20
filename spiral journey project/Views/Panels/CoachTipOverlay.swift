import SwiftUI
import SpiralKit

/// Floating overlay showing the current coach insight.
/// Appears above the action bar with a glass pill style.
struct CoachTipOverlay: View {
    let insight: CoachInsight
    let onDismiss: () -> Void
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: severityIcon)
                    .foregroundStyle(severityColor)
                Text(localizedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                    .lineLimit(2)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                }
                .buttonStyle(.plain)
            }
            Text(localizedAction)
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var localizedTitle: String {
        let key = "coach.\(insight.issueKey.rawValue).title"
        let localized = NSLocalizedString(key, bundle: bundle, comment: "")
        return localized != key ? localized : insight.title
    }

    private var localizedAction: String {
        let key = "coach.\(insight.issueKey.rawValue).action"
        let localized = NSLocalizedString(key, bundle: bundle, comment: "")
        return localized != key ? localized : insight.action
    }

    private var severityIcon: String {
        switch insight.severity {
        case .info:     return "info.circle.fill"
        case .mild:     return "exclamationmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .urgent:   return "flame.fill"
        }
    }

    private var severityColor: Color {
        switch insight.severity {
        case .info:     return SpiralColors.accent
        case .mild:     return SpiralColors.moderate
        case .moderate: return .orange
        case .urgent:   return SpiralColors.poor
        }
    }
}
