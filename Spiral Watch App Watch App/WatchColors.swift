import SwiftUI

/// Color palette for the Watch app.
/// Adaptive colors are backed by Asset Catalog color sets with dark + light variants.
/// NOTE: Asset catalog colors (Color("Name")) do NOT reliably resolve in watchOS when
/// the color scheme is forced programmatically. Use appearance-aware helpers instead.
enum SpiralColors {
    static let bg       = Color("SpiralBg")
    static let surface  = Color("SpiralSurface")
    static let accent   = Color("SpiralAccent")
    static let accentDim = Color("SpiralAccentDim")
    static let muted    = Color("SpiralMuted")
    static let text     = Color("SpiralText")
    static let border   = Color("SpiralBorder")

    // MARK: - Appearance-aware helpers (use these in Watch views)

    /// Returns the correct bg color without relying on asset catalog trait resolution.
    static func bg(_ appearance: String) -> Color {
        appearance == "light" ? Color(hex: "f5f5f7") : Color(hex: "0c0e14")
    }
    /// Muted label color — boosted for legibility on dark bg.
    static func muted(_ appearance: String) -> Color {
        appearance == "light" ? Color(hex: "6b7280") : Color(hex: "8899aa")
    }
    /// Primary text color.
    static func text(_ appearance: String) -> Color {
        appearance == "light" ? Color(hex: "1f2937") : Color(hex: "c8cdd8")
    }
    /// Card / surface color.
    static func surface(_ appearance: String) -> Color {
        appearance == "light" ? Color(hex: "ffffff") : Color(hex: "12151e")
    }
    /// Separator / border color.
    static func border(_ appearance: String) -> Color {
        appearance == "light" ? Color(hex: "d1d5db") : Color(hex: "2a3040")
    }
    static let good     = Color(hex: "#5bffa8")
    static let moderate = Color(hex: "#f5c842")
    static let poor     = Color(hex: "#e05252")
    /// Sleep arc / bedtime indicator — purple, theme-independent
    static let sleep    = Color(hex: "#6e3fa0")
    /// Wakeup indicator — amber, theme-independent
    static let wake       = Color(hex: "#f5c842")
    static let awakeSleep = Color(hex: "#f5c842")

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
