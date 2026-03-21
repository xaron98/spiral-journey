import SwiftUI

/// Color palette for Spiral Journey.
/// Theme-adaptive colors (bg, surface, border, muted, text, accent, accentDim) are backed
/// by Asset Catalog color sets with separate dark and light variants.
/// Phase colors and score colors remain constant across both appearances.
enum SpiralColors {
    // Adaptive — defined in Assets.xcassets with dark + light variants
    static let bg          = Color("SpiralBg")
    static let surface     = Color("SpiralSurface")
    static let border      = Color("SpiralBorder")
    static let text        = Color("SpiralText")       // Primary — titles, values, headlines
    static let muted       = Color("SpiralMuted")      // Secondary — card body, subtitles, descriptions
    static let subtle      = Color("SpiralSubtle")     // Tertiary — eyebrows, units, axis labels
    static let faint       = Color("SpiralFaint")      // Quaternary — date lines, placeholders, microcopy
    static let accent      = Color("SpiralAccent")
    static let accentDim   = Color("SpiralAccentDim")

    // Sleep phase colors
    static let deepSleep   = Color(hex: "1a1a6e")
    static let remSleep    = Color(hex: "6e3fa0")
    static let lightSleep  = Color(hex: "5b8bd4")
    static let awakeSleep  = Color(hex: "f5c842")
    static let weekend     = Color(hex: "4a3a6a")

    // Score status colors — adaptive: bright for dark mode, high-contrast for light mode
    static let good        = Color("SpiralGood")     // dark #5bffa8 · light #198752
    static let moderate    = Color("SpiralModerate") // dark #f5c842 · light #854D0E
    static let poor        = Color("SpiralPoor")     // dark #f05050 · light #B91C1C

    // Context block colors — electric blue family
    static let contextPrimary   = Color(hex: "3B82F6")  // electric blue
    static let contextSecondary = Color(hex: "60A5FA")  // lighter variant

    /// Viridis-like interpolation for activity heatmaps (0 = dark blue, 1 = yellow-green)
    static func viridis(_ t: Double) -> Color {
        let v = max(0, min(1, t))
        let r = 0.267 + 0.660 * v
        let g = 0.005 + 0.825 * v
        let b = 0.329 - 0.109 * v
        return Color(red: r, green: g, blue: b)
    }

    /// RdBu diverging scale: -1 = red, 0 = white, +1 = blue
    static func rdBu(_ t: Double) -> Color {
        let v = max(-1, min(1, t))
        if v >= 0 {
            return Color(red: 1 - v * 0.7, green: 1 - v * 0.6, blue: 1.0)
        } else {
            let a = -v
            return Color(red: 1.0, green: 1 - a * 0.6, blue: 1 - a * 0.7)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}
