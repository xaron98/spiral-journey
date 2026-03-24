import Foundation

/// Educational article for the "Learn" section.
public struct LearnArticle: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String           // SF Symbol
    public let sections: [LearnSection]
    public let quiz: [QuizQuestion]
}

public struct LearnSection: Codable, Sendable {
    public let header: String
    public let body: String
    public let funFact: String?       // "Did you know?" callout
}

public struct QuizQuestion: Codable, Identifiable, Sendable {
    public var id: String { question }
    public let question: String
    public let options: [String]
    public let correct: Int           // 0-based index
}

/// Loads localized learn content from bundled JSON files.
public enum LearnContentLoader {

    public static func load(locale: String) -> [LearnArticle] {
        // Try exact match first (e.g. "zh-Hans"), then prefix (e.g. "zh"), then fallback to "en"
        let candidates = [locale, String(locale.prefix(2)), "en"]
        for lang in candidates {
            if let url = Bundle.module.url(forResource: lang, withExtension: "json", subdirectory: "Learn"),
               let data = try? Data(contentsOf: url),
               let content = try? JSONDecoder().decode(LearnFile.self, from: data) {
                return content.articles
            }
        }
        return []
    }

    private struct LearnFile: Codable {
        let articles: [LearnArticle]
    }
}
