# App Themes System — 5 Visual Themes with Light/Dark Support

## Overview

Add a theme system with 5 selectable visual themes that change the entire app's look: background, cards, accent color, sleep phase colors, and spiral aesthetics. Each theme supports iOS light/dark mode automatically.

## Themes

### 1. Medianoche (default — current look)
The existing purple/dark theme. No changes needed — this IS the current app.

- **Accent:** `#7c3aed` (purple)
- **Deep sleep:** `#1a1a6e` (deep violet)
- **REM:** `#6e3fa0` (purple)
- **Light sleep:** `#5b8bd4` (light blue)
- **Awake:** `#fbbf24` (amber)
- **Dark bg:** `#0a0a1a` / **Light bg:** `#f5f5f7`
- **Personality:** Deep, scientific, nocturnal

### 2. Aurora
Inspired by northern lights — greens, teals, and soft pinks.

- **Accent:** `#34d399` (emerald)
- **Deep sleep:** `#064e3b` (deep emerald)
- **REM:** `#2dd4bf` (teal)
- **Light sleep:** `#a7f3d0` (mint)
- **Awake:** `#fbbf24` (amber — kept for consistency)
- **Dark bg:** `#021a0f` / **Light bg:** `#f0fdf4`
- **Personality:** Natural, calm, Nordic

### 3. Oceano
Deep ocean blues with coral accents.

- **Accent:** `#0ea5e9` (sky blue)
- **Deep sleep:** `#0c1445` (deep navy)
- **REM:** `#3b82f6` (blue)
- **Light sleep:** `#7dd3fc` (light sky)
- **Awake:** `#fb923c` (coral orange)
- **Dark bg:** `#020617` / **Light bg:** `#f0f9ff`
- **Personality:** Deep, tranquil, immersive

### 4. Amanecer
Warm sunrise palette — golds, peaches, soft reds.

- **Accent:** `#f59e0b` (amber gold)
- **Deep sleep:** `#78350f` (deep brown)
- **REM:** `#f97316` (orange)
- **Light sleep:** `#fde68a` (soft gold)
- **Awake:** `#ef4444` (warm red)
- **Dark bg:** `#1c0a00` / **Light bg:** `#fffbeb`
- **Personality:** Warm, energetic, optimistic

### 5. Minimalista
Monochrome — pure black/white with silver accents. No color in phases.

- **Accent:** `#a1a1aa` (zinc/silver)
- **Deep sleep:** `#3f3f46` (dark zinc)
- **REM:** `#71717a` (zinc)
- **Light sleep:** `#a1a1aa` (light zinc)
- **Awake:** `#d4d4d8` (silver)
- **Dark bg:** `#09090b` / **Light bg:** `#fafafa`
- **Personality:** Clean, clinical, data-focused

## Architecture

### ThemeDefinition

```swift
struct ThemeDefinition: Identifiable, Codable {
    let id: String           // "midnight", "aurora", "ocean", "sunrise", "minimal"
    let nameKey: String      // localization key

    // Accent
    let accentHex: String

    // Sleep phases (dark mode values — light mode derived automatically)
    let deepSleepHex: String
    let remSleepHex: String
    let lightSleepHex: String
    let awakeHex: String

    // Backgrounds
    let darkBgHex: String
    let lightBgHex: String

    // Surface/card backgrounds
    let darkSurfaceHex: String
    let lightSurfaceHex: String
}
```

All 5 themes defined as static constants in a `ThemeLibrary` enum.

### Integration with SpiralColors

`SpiralColors` currently reads from Asset Catalog colors. The theme system changes this:

1. `SpiralStore` gets a new property: `selectedTheme: String = "midnight"`
2. `SpiralColors` reads from the active `ThemeDefinition` instead of hardcoded Asset Catalog values
3. Colors that are currently adaptive (light/dark) check `colorScheme` and pick the right hex from the theme

### SpiralColors Changes

Current approach (Asset Catalog):
```swift
static let accent = Color("SpiralAccent") // reads from xcassets
```

New approach (theme-driven):
```swift
static func accent(for theme: ThemeDefinition, scheme: ColorScheme) -> Color {
    Color(hex: theme.accentHex)
}
```

But this would require passing theme/scheme everywhere. Better approach: use an `@Observable ThemeManager` in the environment that provides resolved colors:

```swift
@Observable class ThemeManager {
    var current: ThemeDefinition = ThemeLibrary.midnight
    var scheme: ColorScheme = .dark

    var accent: Color { Color(hex: current.accentHex) }
    var bg: Color { scheme == .dark ? Color(hex: current.darkBgHex) : Color(hex: current.lightBgHex) }
    var deepSleep: Color { Color(hex: current.deepSleepHex) }
    // ... etc
}
```

Then `SpiralColors` static properties delegate to the shared `ThemeManager`:
```swift
enum SpiralColors {
    @MainActor static var shared = ThemeManager()

    static var accent: Color { shared.accent }
    static var bg: Color { shared.bg }
    // ... etc
}
```

This way ALL existing code that uses `SpiralColors.accent` continues to work — no changes needed at call sites.

### Settings UI

New row in Settings: "Tema" / "Theme" — opens a picker with 5 visual previews:
- Each theme shown as a mini circle or card with its accent color + name
- Selecting a theme instantly updates the entire app

### Persistence

`SpiralStore.selectedTheme: String` persisted in the existing JSON settings. On launch, `ThemeManager` loads the selected theme.

## Files Changed

| Action | File | Notes |
|--------|------|-------|
| Create | `spiral journey project/Theme/ThemeDefinition.swift` | Theme struct + ThemeLibrary with 5 themes |
| Create | `spiral journey project/Theme/ThemeManager.swift` | @Observable manager, resolves colors for current theme + scheme |
| Modify | `spiral journey project/Theme/SpiralColors.swift` | Delegate to ThemeManager instead of Asset Catalog |
| Modify | `spiral journey project/Services/SpiralStore.swift` | Add `selectedTheme` property |
| Modify | `spiral journey project/Views/Tabs/SettingsTab.swift` | Add theme picker |
| Modify | `spiral journey project/Localizable.xcstrings` | Theme name keys |
| Modify | `spiral journey project/Views/Spiral/SpiralView.swift` | Phase colors from theme (may already work if SpiralColors delegates correctly) |

## Scope Boundaries

- Only the 5 colors that define sleep phases + accent + bg + surface change per theme
- Score colors (good/moderate/poor) stay fixed — they're semantic, not aesthetic
- The `liquidGlass` modifier uses `.ultraThinMaterial` which adapts to bg automatically
- Context block colors (blue) may need per-theme adjustment or stay fixed
- MiniHelixView strand colors need to follow the theme

## Migration

The current "Medianoche" theme IS the existing app. No migration needed — if `selectedTheme` is nil or "midnight", behavior is identical to current.
