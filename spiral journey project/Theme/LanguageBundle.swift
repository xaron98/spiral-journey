import SwiftUI

// MARK: - Dynamic Language Bundle

/// Returns the app bundle for a given BCP 47 locale identifier.
/// Falls back to the main bundle if the language is not found.
func languageBundle(for localeIdentifier: String) -> Bundle {
    // Try exact match first, then language-only prefix
    for candidate in [localeIdentifier, String(localeIdentifier.prefix(2))] {
        if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
    }
    return Bundle.main
}

// MARK: - Environment Key

private struct LanguageBundleKey: EnvironmentKey {
    static let defaultValue: Bundle = .main
}

extension EnvironmentValues {
    /// The localized string bundle matching the user's chosen in-app language.
    var languageBundle: Bundle {
        get { self[LanguageBundleKey.self] }
        set { self[LanguageBundleKey.self] = newValue }
    }
}
