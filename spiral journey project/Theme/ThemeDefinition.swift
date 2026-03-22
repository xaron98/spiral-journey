import SwiftUI

/// Defines all colors for a visual theme. Each theme provides dark and light variants
/// for adaptive colors, plus fixed colors for sleep phases.
struct ThemeDefinition: Identifiable, Codable, Equatable {
    let id: String
    let nameKey: String  // localization key

    // Accent
    let accentHex: String
    let accentDimHex: String

    // Backgrounds (dark / light)
    let darkBgHex: String
    let lightBgHex: String
    let darkSurfaceHex: String
    let lightSurfaceHex: String
    let darkBorderHex: String
    let lightBorderHex: String

    // Text (dark / light)
    let darkTextHex: String
    let lightTextHex: String
    let darkMutedHex: String
    let lightMutedHex: String
    let darkSubtleHex: String
    let lightSubtleHex: String
    let darkFaintHex: String
    let lightFaintHex: String

    // Sleep phases (constant across light/dark)
    let deepSleepHex: String
    let remSleepHex: String
    let lightSleepHex: String
    let awakeHex: String
    let weekendHex: String

    // Context blocks
    let contextPrimaryHex: String
    let contextSecondaryHex: String
}

/// All available themes.
enum ThemeLibrary {

    static let midnight = ThemeDefinition(
        id: "midnight", nameKey: "theme.midnight",
        accentHex: "7c3aed", accentDimHex: "6d28d9",
        darkBgHex: "0a0a1a", lightBgHex: "f5f5f7",
        darkSurfaceHex: "1a1a2e", lightSurfaceHex: "ffffff",
        darkBorderHex: "2a2a3e", lightBorderHex: "d1d1d6",
        darkTextHex: "f0f0f5", lightTextHex: "1a1a2e",
        darkMutedHex: "a0a0b0", lightMutedHex: "6b6b7b",
        darkSubtleHex: "6b6b7b", lightSubtleHex: "8e8e9e",
        darkFaintHex: "3a3a4e", lightFaintHex: "c0c0cc",
        deepSleepHex: "7c3aed", remSleepHex: "a78bfa",
        lightSleepHex: "c4b5fd", awakeHex: "fbbf24",
        weekendHex: "4a3a6a",
        contextPrimaryHex: "3B82F6", contextSecondaryHex: "60A5FA"
    )

    static let aurora = ThemeDefinition(
        id: "aurora", nameKey: "theme.aurora",
        accentHex: "34d399", accentDimHex: "059669",
        darkBgHex: "021a0f", lightBgHex: "f0fdf4",
        darkSurfaceHex: "0a2a1a", lightSurfaceHex: "ffffff",
        darkBorderHex: "1a3a2a", lightBorderHex: "bbf7d0",
        darkTextHex: "e8f5e9", lightTextHex: "0a2a1a",
        darkMutedHex: "86b89a", lightMutedHex: "4a7a5e",
        darkSubtleHex: "4a7a5e", lightSubtleHex: "6b9a7e",
        darkFaintHex: "1a3a2a", lightFaintHex: "bbf7d0",
        deepSleepHex: "064e3b", remSleepHex: "2dd4bf",
        lightSleepHex: "a7f3d0", awakeHex: "fbbf24",
        weekendHex: "0d503d",
        contextPrimaryHex: "14b8a6", contextSecondaryHex: "5eead4"
    )

    static let ocean = ThemeDefinition(
        id: "ocean", nameKey: "theme.ocean",
        accentHex: "0ea5e9", accentDimHex: "0284c7",
        darkBgHex: "020617", lightBgHex: "f0f9ff",
        darkSurfaceHex: "0c1a3a", lightSurfaceHex: "ffffff",
        darkBorderHex: "1e3a5f", lightBorderHex: "bae6fd",
        darkTextHex: "e0f2fe", lightTextHex: "0c1a3a",
        darkMutedHex: "7dd3fc", lightMutedHex: "0369a1",
        darkSubtleHex: "38bdf8", lightSubtleHex: "0ea5e9",
        darkFaintHex: "1e3a5f", lightFaintHex: "bae6fd",
        deepSleepHex: "0c1445", remSleepHex: "3b82f6",
        lightSleepHex: "7dd3fc", awakeHex: "fb923c",
        weekendHex: "1e3a5f",
        contextPrimaryHex: "06b6d4", contextSecondaryHex: "67e8f9"
    )

    static let sunrise = ThemeDefinition(
        id: "sunrise", nameKey: "theme.sunrise",
        accentHex: "f59e0b", accentDimHex: "d97706",
        darkBgHex: "1c0a00", lightBgHex: "fffbeb",
        darkSurfaceHex: "2a1505", lightSurfaceHex: "ffffff",
        darkBorderHex: "4a2a10", lightBorderHex: "fde68a",
        darkTextHex: "fef3c7", lightTextHex: "1c0a00",
        darkMutedHex: "d4a060", lightMutedHex: "92400e",
        darkSubtleHex: "92400e", lightSubtleHex: "b45309",
        darkFaintHex: "4a2a10", lightFaintHex: "fde68a",
        deepSleepHex: "78350f", remSleepHex: "f97316",
        lightSleepHex: "fde68a", awakeHex: "ef4444",
        weekendHex: "5a3510",
        contextPrimaryHex: "fb923c", contextSecondaryHex: "fdba74"
    )

    static let minimal = ThemeDefinition(
        id: "minimal", nameKey: "theme.minimal",
        accentHex: "a1a1aa", accentDimHex: "71717a",
        darkBgHex: "09090b", lightBgHex: "fafafa",
        darkSurfaceHex: "18181b", lightSurfaceHex: "ffffff",
        darkBorderHex: "27272a", lightBorderHex: "d4d4d8",
        darkTextHex: "e4e4e7", lightTextHex: "18181b",
        darkMutedHex: "a1a1aa", lightMutedHex: "52525b",
        darkSubtleHex: "71717a", lightSubtleHex: "71717a",
        darkFaintHex: "3f3f46", lightFaintHex: "d4d4d8",
        deepSleepHex: "3f3f46", remSleepHex: "71717a",
        lightSleepHex: "a1a1aa", awakeHex: "d4d4d8",
        weekendHex: "27272a",
        contextPrimaryHex: "71717a", contextSecondaryHex: "a1a1aa"
    )

    static let all: [ThemeDefinition] = [midnight, aurora, ocean, sunrise, minimal]

    static func theme(for id: String) -> ThemeDefinition {
        all.first { $0.id == id } ?? midnight
    }
}
