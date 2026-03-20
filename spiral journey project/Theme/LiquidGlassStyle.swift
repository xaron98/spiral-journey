import SwiftUI

// MARK: - Liquid Glass View Modifier

/// Applies a frosted-glass "Liquid Glass" aesthetic to any view.
/// Uses `.ultraThinMaterial` with a specular gradient stroke and soft shadow
/// to simulate Apple's Glassmorphism design language.
struct LiquidGlassStyle: ViewModifier {
    var isCircular: Bool = false
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = isCircular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        content
            .background(.ultraThinMaterial)
            .clipShape(shape)
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .clear,
                                .white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 8)
    }
}

extension View {
    /// Applies the Liquid Glass style (frosted blur + specular stroke + shadow).
    /// - Parameters:
    ///   - circular: If `true`, clips to a `Circle` instead of a rounded rectangle.
    ///   - cornerRadius: Corner radius for the rounded rectangle (ignored when circular).
    func liquidGlass(circular: Bool = false, cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassStyle(isCircular: circular, cornerRadius: cornerRadius))
    }
}
