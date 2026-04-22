import SwiftUI

/// Reusable card component for the DNA mode view.
///
/// Compact cards (isLarge = false) show a chevron indicating tap-to-expand.
/// Large cards show content inline without expansion affordance.
struct DNACardView<Content: View>: View {
    let title: String
    let icon: String
    let isLarge: Bool
    /// Optional action for a small help (`?`) button rendered at the top
    /// right of the card. Tap events on the button are isolated from the
    /// outer card tap gesture so the help sheet can open without also
    /// pushing the card's primary destination.
    let onHelpTap: (() -> Void)?
    let content: Content

    init(_ title: String,
         icon: String,
         isLarge: Bool = false,
         onHelpTap: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.isLarge = isLarge
        self.onHelpTap = onHelpTap
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                if let onHelpTap {
                    Button(action: onHelpTap) {
                        Image(systemName: "questionmark.circle")
                            .font(.footnote)
                            .foregroundStyle(SpiralColors.muted)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !isLarge {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
