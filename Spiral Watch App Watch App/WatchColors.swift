import SwiftUI

/// Color palette for the Watch app.
/// Adaptive colors are backed by Asset Catalog color sets with dark + light variants.
enum SpiralColors {
    static let bg       = Color("SpiralBg")
    static let surface  = Color("SpiralSurface")
    static let accent   = Color("SpiralAccent")
    static let accentDim = Color("SpiralAccentDim")
    static let muted    = Color("SpiralMuted")
    static let text     = Color("SpiralText")
    static let border   = Color("SpiralBorder")
    static let good     = Color(hex: "#5bffa8")
    static let moderate = Color(hex: "#f5c842")
    static let poor     = Color(hex: "#e05252")
    /// Sleep arc / bedtime indicator — purple, theme-independent
    static let sleep    = Color(hex: "#6e3fa0")
    /// Wakeup indicator — amber, theme-independent
    static let wake     = Color(hex: "#f5c842")

    /// Viridis-style colour ramp for activity intensity (0→1).
    static func viridis(_ t: Double) -> Color {
        let t = max(0, min(1, t))
        let r = 0.267 + t * (0.004 - 0.267) + t * t * (0.330 - 0.004 - 0.267)
        let g = 0.005 + t * (0.658 - 0.005)
        let b = 0.329 + t * (0.498 - 0.329)
        return Color(red: max(0, min(1, r)), green: max(0, min(1, g)), blue: max(0, min(1, b)))
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
