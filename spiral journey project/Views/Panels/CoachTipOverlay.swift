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
        localizedCoachString(
            "coach.issue.\(insight.issueKey.rawValue).title",
            fallback: insight.title,
            args: insight.args,
            stringArgs: insight.stringArgs
        )
    }

    private var localizedAction: String {
        localizedCoachString(
            "coach.issue.\(insight.issueKey.rawValue).action",
            fallback: insight.action,
            args: insight.args,
            stringArgs: insight.stringArgs
        )
    }

    /// Resolve a coach localization key with optional format args; falls back to English `fallback`.
    private func localizedCoachString(_ key: String, fallback: String, args: [Double], stringArgs: [String] = []) -> String {
        let raw = NSLocalizedString(key, bundle: bundle, comment: "")
        let resolved = raw == key ? fallback : raw
        if !stringArgs.isEmpty {
            switch stringArgs.count {
            case 1: return String(format: resolved, stringArgs[0])
            case 2: return String(format: resolved, stringArgs[0], stringArgs[1])
            default: return resolved
            }
        }
        guard !args.isEmpty else { return resolved }
        switch args.count {
        case 1: return String(format: resolved, args[0])
        case 2: return String(format: resolved, args[0], args[1])
        case 3: return String(format: resolved, args[0], args[1], args[2])
        default: return resolved
        }
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
