import SwiftUI

/// Reusable card component for the DNA mode view.
///
/// Compact cards (isLarge = false) show a chevron indicating tap-to-expand.
/// Large cards show content inline without expansion affordance.
struct DNACardView<Content: View>: View {
    let title: String
    let icon: String
    let isLarge: Bool
    let content: Content

    init(_ title: String, icon: String, isLarge: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.isLarge = isLarge
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
