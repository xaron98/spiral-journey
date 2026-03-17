import Testing
import Foundation
@testable import SpiralKit

@Suite("WeekSequence")
struct WeekSequenceTests {

    // MARK: - Helpers

    private func makeRecord(day: Int, bedtime: Double = 23, wakeup: Double = 7, duration: Double = 8) -> SleepRecord {
        SleepRecord(
            day: day,
            date: Date(),
            isWeekend: day % 7 >= 5,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: (0..<24).map { h in
                let asleep = bedtime > wakeup
                    ? (Double(h) >= bedtime || Double(h) < wakeup)
                    : (Double(h) >= bedtime && Double(h) < wakeup)
                return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
            },
            cosinor: .empty
        )
    }

    private func makeNucleotides(count: Int) -> [DayNucleotide] {
        (0..<count).map { day in
            DayNucleotide.encode(record: makeRecord(day: day), events: [])
        }
    }

    // MARK: - Sequence Generation

    @Test("7 nucleotides produce exactly 1 sequence")
    func testSevenNucleotidesOneSequence() {
        let nucs = makeNucleotides(count: 7)
        let sequences = WeekSequence.generateSequences(from: nucs)
        #expect(sequences.count == 1)
        #expect(sequences[0].startDay == 0)
        #expect(sequences[0].nucleotides.count == 7)
    }

    @Test("14 nucleotides produce exactly 8 sequences")
    func testFourteenNucleotidesEightSequences() {
        let nucs = makeNucleotides(count: 14)
        let sequences = WeekSequence.generateSequences(from: nucs)
        #expect(sequences.count == 8)

        // First sequence starts at day 0, last at day 7
        #expect(sequences[0].startDay == 0)
        #expect(sequences[7].startDay == 7)
    }

    @Test("Fewer than 7 nucleotides produce empty result")
    func testTooFewNucleotides() {
        let nucs6 = makeNucleotides(count: 6)
        #expect(WeekSequence.generateSequences(from: nucs6).isEmpty)

        let nucs1 = makeNucleotides(count: 1)
        #expect(WeekSequence.generateSequences(from: nucs1).isEmpty)

        #expect(WeekSequence.generateSequences(from: []).isEmpty)
    }

    @Test("Each nucleotide in a sequence has 16 features")
    func testFeatureCountInSequence() {
        let nucs = makeNucleotides(count: 7)
        let sequences = WeekSequence.generateSequences(from: nucs)
        let seq = sequences[0]
        for nuc in seq.nucleotides {
            #expect(nuc.features.count == DayNucleotide.featureCount)
        }
    }

    // MARK: - Matrix

    @Test("Matrix has dimensions 7 x 16")
    func testMatrixDimensions() {
        let nucs = makeNucleotides(count: 7)
        let sequences = WeekSequence.generateSequences(from: nucs)
        let matrix = sequences[0].matrix
        #expect(matrix.count == 7)
        for row in matrix {
            #expect(row.count == 16)
        }
    }

    // MARK: - Sorting

    @Test("Nucleotides are sorted by day before windowing")
    func testSortedByDay() {
        // Provide nucleotides in reverse order
        let nucs = (0..<7).reversed().map { day in
            DayNucleotide.encode(record: makeRecord(day: day), events: [])
        }
        let sequences = WeekSequence.generateSequences(from: nucs)
        #expect(sequences.count == 1)
        // Days should be in ascending order within the sequence
        let days = sequences[0].nucleotides.map(\.day)
        #expect(days == [0, 1, 2, 3, 4, 5, 6])
    }

    // MARK: - Sliding Window Correctness

    @Test("Sliding windows overlap correctly")
    func testSlidingWindowOverlap() {
        let nucs = makeNucleotides(count: 10)
        let sequences = WeekSequence.generateSequences(from: nucs)
        #expect(sequences.count == 4) // 10 - 7 + 1 = 4

        // Window 0: days 0-6, Window 1: days 1-7, etc.
        for (i, seq) in sequences.enumerated() {
            #expect(seq.startDay == i)
            let expectedDays = Array(i..<(i + 7))
            let actualDays = seq.nucleotides.map(\.day)
            #expect(actualDays == expectedDays)
        }
    }
}
