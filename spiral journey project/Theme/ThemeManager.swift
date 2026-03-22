import SwiftUI

/// Resolves theme colors based on the active theme and current color scheme.
/// Injected into the environment so all views can access theme-aware colors.
@Observable
@MainActor
final class ThemeManager {
    var current: ThemeDefinition = ThemeLibrary.midnight
    var scheme: ColorScheme = .dark

    // MARK: - Adaptive colors (change with light/dark mode)

    var bg: Color      { scheme == .dark ? Color(hex: current.darkBgHex) : Color(hex: current.lightBgHex) }
    var surface: Color  { scheme == .dark ? Color(hex: current.darkSurfaceHex) : Color(hex: current.lightSurfaceHex) }
    var border: Color   { scheme == .dark ? Color(hex: current.darkBorderHex) : Color(hex: current.lightBorderHex) }
    var text: Color     { scheme == .dark ? Color(hex: current.darkTextHex) : Color(hex: current.lightTextHex) }
    var muted: Color    { scheme == .dark ? Color(hex: current.darkMutedHex) : Color(hex: current.lightMutedHex) }
    var subtle: Color   { scheme == .dark ? Color(hex: current.darkSubtleHex) : Color(hex: current.lightSubtleHex) }
    var faint: Color    { scheme == .dark ? Color(hex: current.darkFaintHex) : Color(hex: current.lightFaintHex) }

    // MARK: - Accent (theme-specific, same in light/dark)

    var accent: Color    { Color(hex: current.accentHex) }
    var accentDim: Color { Color(hex: current.accentDimHex) }

    // MARK: - Sleep phases (theme-specific, constant across light/dark)

    var deepSleep: Color  { Color(hex: current.deepSleepHex) }
    var remSleep: Color   { Color(hex: current.remSleepHex) }
    var lightSleep: Color { Color(hex: current.lightSleepHex) }
    var awakeSleep: Color { Color(hex: current.awakeHex) }
    var weekend: Color    { Color(hex: current.weekendHex) }

    // MARK: - Context blocks

    var contextPrimary: Color   { Color(hex: current.contextPrimaryHex) }
    var contextSecondary: Color { Color(hex: current.contextSecondaryHex) }

    // MARK: - Apply theme

    func apply(_ theme: ThemeDefinition) {
        current = theme
    }

    func apply(id: String) {
        current = ThemeLibrary.theme(for: id)
    }
}
