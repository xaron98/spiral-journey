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
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(SpiralColors.bg)
                    RoundedRectangle(cornerRadius: 8).stroke(SpiralColors.border.opacity(0.6), lineWidth: 0.8)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CardBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var hasMaterial: Bool = true
    var borderOpacity: Double = 0.4

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                if hasMaterial {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial)
                }
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(SpiralColors.surface.opacity(0.35))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(SpiralColors.border.opacity(borderOpacity), lineWidth: 0.8)
            }
        )
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

    /// Reusable card background with material, tinted surface, and border stroke.
    func cardBackground(cornerRadius: CGFloat = 16, hasMaterial: Bool = true, borderOpacity: Double = 0.4) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius, hasMaterial: hasMaterial, borderOpacity: borderOpacity))
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
                .lineLimit(1)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.accent)
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
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(SpiralColors.subtle)
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
