import SwiftUI

// MARK: - Dynamic Language Bundle

func languageBundle(for localeIdentifier: String) -> Bundle {
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
    var languageBundle: Bundle {
        get { self[LanguageBundleKey.self] }
        set { self[LanguageBundleKey.self] = newValue }
    }
}
