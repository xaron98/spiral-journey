import SwiftUI

// MARK: - ViewModifiers

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(SpiralColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SpiralColors.border, lineWidth: 1)
            )
    }
}

struct StatCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(SpiralColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - View Extensions

extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }

    func statCardStyle() -> some View {
        modifier(StatCardModifier())
    }
}

// MARK: - Reusable Components

/// Compact stat display card used throughout the app.
struct StatCard: View {
    let label: String
    let value: String
    let sub: String?

    init(_ label: String, value: String, sub: String? = nil) {
        self.label = label
        self.value = value
        self.sub = sub
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
                .lineLimit(1)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.accentDim)
            }
        }
        .statCardStyle()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section title label.
struct PanelTitle: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(SpiralColors.muted)
            .tracking(2)
    }
}

/// Toggle-style pill button.
struct PillButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? SpiralColors.accentDim : SpiralColors.border)
                .foregroundStyle(isActive ? SpiralColors.accent : SpiralColors.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? SpiralColors.accentDim : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
