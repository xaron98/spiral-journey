import Foundation

/// A detected circadian disorder pattern.
public struct DisorderSignature: Codable, Identifiable, Sendable {
    public var id: String         // "dswpd", "aswpd", "n24swd", "iswrd", "normal"
    public var label: String
    public var fullLabel: String
    public var confidence: Double // 0-1
    public var description: String
    public var hexColor: String

    public init(id: String, label: String, fullLabel: String, confidence: Double, description: String, hexColor: String) {
        self.id = id
        self.label = label
        self.fullLabel = fullLabel
        self.confidence = confidence
        self.description = description
        self.hexColor = hexColor
    }
}
