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
    public var matrix: [[Double]] { nucleotides.map(\.features) }

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
            WeekSequence(startDay: sorted[i].day, nucleotides: Array(sorted[i..<(i + 7)]))
        }
    }
}
