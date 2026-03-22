import SwiftUI

/// Color palette for Spiral Journey.
///
/// All colors delegate to the shared ThemeManager, which resolves based on
/// the active theme + current color scheme. Existing call sites (SpiralColors.accent,
/// SpiralColors.bg, etc.) continue to work without changes.
enum SpiralColors {

    /// Shared theme manager — set once at app launch, updated when theme changes.
    @MainActor static var theme = ThemeManager()

    // MARK: - Adaptive colors (theme + light/dark aware)

    @MainActor static var bg:        Color { theme.bg }
    @MainActor static var surface:   Color { theme.surface }
    @MainActor static var border:    Color { theme.border }
    @MainActor static var text:      Color { theme.text }
    @MainActor static var muted:     Color { theme.muted }
    @MainActor static var subtle:    Color { theme.subtle }
    @MainActor static var faint:     Color { theme.faint }
    @MainActor static var accent:    Color { theme.accent }
    @MainActor static var accentDim: Color { theme.accentDim }

    // MARK: - Sleep phase colors (theme-specific, constant across light/dark)

    @MainActor static var deepSleep:  Color { theme.deepSleep }
    @MainActor static var remSleep:   Color { theme.remSleep }
    @MainActor static var lightSleep: Color { theme.lightSleep }
    @MainActor static var awakeSleep: Color { theme.awakeSleep }
    @MainActor static var weekend:    Color { theme.weekend }

    // MARK: - Context block colors

    @MainActor static var contextPrimary:   Color { theme.contextPrimary }
    @MainActor static var contextSecondary: Color { theme.contextSecondary }

    // MARK: - Score status colors — fixed across all themes (semantic, not aesthetic)

    static let good     = Color("SpiralGood")     // dark #5bffa8 · light #198752
    static let moderate = Color("SpiralModerate") // dark #f5c842 · light #854D0E
    static let poor     = Color("SpiralPoor")     // dark #f05050 · light #B91C1C

    // MARK: - Interpolation functions (unchanged)

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
