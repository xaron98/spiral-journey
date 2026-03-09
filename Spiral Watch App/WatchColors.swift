import SwiftUI

/// Shared color utilities for the Watch app.
/// Mirrors the palette from SpiralColors in the iOS target.
enum SpiralColors {
    static let bg       = Color(hex: "#0c0e14")
    static let surface  = Color(hex: "#12151e")
    static let accent   = Color(hex: "#5bffa8")
    static let muted    = Color(hex: "#555566")
    static let text     = Color(hex: "#c8cdd8")
    static let good     = Color(hex: "#5bffa8")
    static let poor     = Color(hex: "#e05252")

    /// Viridis-style colour ramp for activity intensity (0→1).
    static func viridis(_ t: Double) -> Color {
        let t = max(0, min(1, t))
        let r = 0.267 + t * (0.004 - 0.267) + t * t * (0.330 - 0.004 - 0.267)
        let g = 0.005 + t * (0.658 - 0.005)
        let b = 0.329 + t * (0.498 - 0.329)
        return Color(red: max(0,min(1,r)), green: max(0,min(1,g)), blue: max(0,min(1,b)))
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.flatMap { "\($0)\($0)" }.joined() }
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
