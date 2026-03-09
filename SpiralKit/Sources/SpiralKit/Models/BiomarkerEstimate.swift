import Foundation

/// A circadian biomarker estimated from sleep timing data.
public struct BiomarkerEstimate: Codable, Identifiable, Sendable {
    public var id: String        // key: "dlmo", "car", "tempNadir", "postLunchDip"
    public var label: String
    public var hour: Double      // estimated clock hour
    public var description: String
    public var hexColor: String
    public var symbol: String    // "triangle", "diamond", "square", "circle"

    public init(id: String, label: String, hour: Double, description: String, hexColor: String, symbol: String) {
        self.id = id
        self.label = label
        self.hour = hour
        self.description = description
        self.hexColor = hexColor
        self.symbol = symbol
    }
}
