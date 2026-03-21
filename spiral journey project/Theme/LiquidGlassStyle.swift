import SwiftUI

// MARK: - Liquid Glass View Modifier

/// Frosted-glass card style matching the Coach tab's 3-layer pattern:
/// `.ultraThinMaterial` + optional accent tint fill + accent/border stroke.
/// Clean, minimal — no inner shadows, no specular gradients, no drop shadows.
struct LiquidGlassStyle: ViewModifier {
    var isCircular: Bool = false
    var cornerRadius: CGFloat = 24
    var tintColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = isCircular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        // Tinted cards need stronger contrast in light mode
        let isLight = colorScheme == .light
        let tintFillOpacity:   Double = isLight ? 0.10 : 0.05
        let tintStrokeOpacity: Double = isLight ? 0.35 : 0.18

        content
            .background(
                ZStack {
                    // 1. Frosted material base
                    shape.fill(.ultraThinMaterial)
                    // 2. Optional accent tint wash
                    if let tint = tintColor {
                        shape.fill(tint.opacity(tintFillOpacity))
                    }
                    // 3. Border stroke — accent-colored when tinted, subtle border otherwise
                    if let tint = tintColor {
                        shape.stroke(tint.opacity(tintStrokeOpacity), lineWidth: 0.8)
                    } else {
                        shape.stroke(SpiralColors.border.opacity(0.3), lineWidth: 0.8)
                    }
                }
            )
            .clipShape(shape)
    }
}

extension View {
    /// Applies the frosted-glass card style (material + optional tint + stroke).
    /// Matches the Coach tab's visual language.
    /// - Parameters:
    ///   - circular: If `true`, clips to a `Circle` instead of a rounded rectangle.
    ///   - cornerRadius: Corner radius for the rounded rectangle (ignored when circular).
    ///   - tint: Optional accent color — adds a subtle colored wash and border glow.
    func liquidGlass(circular: Bool = false, cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        modifier(LiquidGlassStyle(isCircular: circular, cornerRadius: cornerRadius, tintColor: tint))
    }
}
