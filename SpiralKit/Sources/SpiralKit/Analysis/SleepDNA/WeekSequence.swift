import Foundation

/// A sliding window of 7 consecutive `DayNucleotide`s forming a week-length sequence.
///
/// Used as input for pattern matching and similarity analysis in the SleepDNA engine.
public struct WeekSequence: Codable, Sendable {
    /// The day index of the first nucleotide in this sequence.
    public let startDay: Int

    /// Exactly 7 nucleotides, one per day.
    public let nucleotides: [DayNucleotide]

    /// The 7x16 feature matrix (one row per day, 16 features per day).
    /// Stored (not computed) to avoid re-allocation on every access.
    public let matrix: [[Double]]

    public init(startDay: Int, nucleotides: [DayNucleotide], matrix: [[Double]]? = nil) {
        self.startDay = startDay
        self.nucleotides = nucleotides
        self.matrix = matrix ?? nucleotides.map(\.features)
    }

    // Custom Codable: decode matrix from nucleotides if missing (backward compat)
    private enum CodingKeys: String, CodingKey {
        case startDay, nucleotides, matrix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDay = try container.decode(Int.self, forKey: .startDay)
        nucleotides = try container.decode([DayNucleotide].self, forKey: .nucleotides)
        matrix = try container.decodeIfPresent([[Double]].self, forKey: .matrix) ?? nucleotides.map(\.features)
    }

    /// Generate all sliding-window week sequences from a collection of nucleotides.
    ///
    /// Nucleotides are sorted by day index, then every contiguous window of 7
    /// produces one `WeekSequence`.
    ///
    /// - Parameter nucleotides: The full set of day nucleotides.
    /// - Returns: An array of `WeekSequence` values. Empty if fewer than 7 nucleotides.
    public static func generateSequences(from nucleotides: [DayNucleotide]) -> [WeekSequence] {
        guard nucleotides.count >= 7 else { return [] }
        let sorted = nucleotides.sorted { $0.day < $1.day }
        return (0...(sorted.count - 7)).map { i in
            let nucs = Array(sorted[i..<(i + 7)])
            return WeekSequence(startDay: sorted[i].day, nucleotides: nucs, matrix: nucs.map(\.features))
        }
    }
}
