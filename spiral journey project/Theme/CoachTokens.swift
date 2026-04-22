import SwiftUI

/// Design tokens for the Coach tab redesign ("Medianoche" palette).
/// Dark-only. Hex values lifted verbatim from the design handoff.
/// Prefer these over `SpiralColors` INSIDE Coach views only — the rest of
/// the app keeps its semantic colors.
enum CoachTokens {

    // MARK: Background / surfaces
    static let bg          = Color(hex: "0A0A1F")
    static let bgSoft      = Color(hex: "12122B")
    static let card        = Color(hex: "1A1A33")
    static let cardHi      = Color(hex: "22224A")

    // MARK: Accents
    static let purple      = Color(hex: "8B5CF6")
    static let purpleDim   = Color(hex: "6D28D9")
    static let purpleDeep  = Color(hex: "4C1D95")
    static let yellow      = Color(hex: "E5B951")
    static let blue        = Color(hex: "5FB3D4")
    static let silver      = Color(hex: "B8B8C8")
    static let green       = Color(hex: "4ADE80")
    static let red         = Color(hex: "F87171")

    // MARK: Text
    static let text        = Color.white
    static let textDim     = Color.white.opacity(0.6)
    static let textFaint   = Color.white.opacity(0.3)

    // MARK: Border
    static let border      = Color.white.opacity(0.08)
    static let borderHi    = Color.white.opacity(0.14)

    // MARK: Radii
    static let rSm: CGFloat = 12
    static let rMd: CGFloat = 18
    static let rLg: CGFloat = 22
    static let rXl: CGFloat = 28
    static let rDock: CGFloat = 32

    // MARK: Mono font (SF Mono via system design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: State-aware score colors (maps 0-100 score → paleta)
    static func accent(forScore s: Int) -> Color {
        switch s {
        case ...49: return yellow
        case 50...69: return purple
        default: return green
        }
    }
}
