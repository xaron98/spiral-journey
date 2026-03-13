import Foundation
import Testing
@testable import SpiralKit

@Suite("Chronotype & MEQ-5 Tests")
struct ChronotypeTests {

    // MARK: - Score boundaries

    @Test("Score 25 → definite morning")
    func maxScore() {
        let result = ChronotypeEngine.score(answers: [5, 5, 5, 5, 5])
        #expect(result != nil)
        #expect(result!.totalScore == 25)
        #expect(result!.chronotype == .definiteMorning)
    }

    @Test("Score 22 → definite morning (boundary)")
    func definiteMorningBoundary() {
        let result = ChronotypeEngine.score(answers: [5, 5, 5, 4, 3])
        #expect(result != nil)
        #expect(result!.totalScore == 22)
        #expect(result!.chronotype == .definiteMorning)
    }

    @Test("Score 21 → moderate morning (boundary)")
    func moderateMorningBoundary() {
        let result = ChronotypeEngine.score(answers: [5, 5, 5, 4, 2])
        #expect(result != nil)
        #expect(result!.totalScore == 21)
        #expect(result!.chronotype == .moderateMorning)
    }

    @Test("Score 18 → moderate morning (lower boundary)")
    func moderateMorningLower() {
        let result = ChronotypeEngine.score(answers: [4, 4, 4, 3, 3])
        #expect(result != nil)
        #expect(result!.totalScore == 18)
        #expect(result!.chronotype == .moderateMorning)
    }

    @Test("Score 17 → intermediate (boundary)")
    func intermediateBoundary() {
        let result = ChronotypeEngine.score(answers: [4, 4, 4, 3, 2])
        #expect(result != nil)
        #expect(result!.totalScore == 17)
        #expect(result!.chronotype == .intermediate)
    }

    @Test("Score 12 → intermediate (lower boundary)")
    func intermediateLower() {
        let result = ChronotypeEngine.score(answers: [3, 3, 2, 2, 2])
        #expect(result != nil)
        #expect(result!.totalScore == 12)
        #expect(result!.chronotype == .intermediate)
    }

    @Test("Score 11 → moderate evening (boundary)")
    func moderateEveningBoundary() {
        let result = ChronotypeEngine.score(answers: [3, 3, 2, 2, 1])
        #expect(result != nil)
        #expect(result!.totalScore == 11)
        #expect(result!.chronotype == .moderateEvening)
    }

    @Test("Score 8 → moderate evening (lower boundary)")
    func moderateEveningLower() {
        let result = ChronotypeEngine.score(answers: [2, 2, 2, 1, 1])
        #expect(result != nil)
        #expect(result!.totalScore == 8)
        #expect(result!.chronotype == .moderateEvening)
    }

    @Test("Score 7 → definite evening (boundary)")
    func definiteEveningBoundary() {
        let result = ChronotypeEngine.score(answers: [2, 2, 1, 1, 1])
        #expect(result != nil)
        #expect(result!.totalScore == 7)
        #expect(result!.chronotype == .definiteEvening)
    }

    @Test("Score 5 → definite evening (minimum)")
    func minScore() {
        let result = ChronotypeEngine.score(answers: [1, 1, 1, 1, 1])
        #expect(result != nil)
        #expect(result!.totalScore == 5)
        #expect(result!.chronotype == .definiteEvening)
    }

    // MARK: - Validation

    @Test("Wrong number of answers returns nil")
    func wrongCount() {
        #expect(ChronotypeEngine.score(answers: [3, 3, 3]) == nil)
        #expect(ChronotypeEngine.score(answers: [3, 3, 3, 3, 3, 3]) == nil)
        #expect(ChronotypeEngine.score(answers: []) == nil)
    }

    @Test("Out of range answers returns nil")
    func outOfRange() {
        #expect(ChronotypeEngine.score(answers: [0, 3, 3, 3, 3]) == nil)
        #expect(ChronotypeEngine.score(answers: [3, 3, 3, 3, 6]) == nil)
    }

    // MARK: - Goal adjustment

    @Test("Adjusted goal for definite morning shifts bedtime earlier")
    func goalDefiniteMorning() {
        let base = SleepGoal.generalHealthDefault
        let adjusted = ChronotypeEngine.adjustedSleepGoal(base: base, chronotype: .definiteMorning)
        #expect(adjusted.targetBedHour == 21.5)
        #expect(adjusted.targetWakeHour == 5.5)
        #expect(adjusted.toleranceMinutes == 120)
    }

    @Test("Adjusted goal for definite evening shifts bedtime later")
    func goalDefiniteEvening() {
        let base = SleepGoal.generalHealthDefault
        let adjusted = ChronotypeEngine.adjustedSleepGoal(base: base, chronotype: .definiteEvening)
        #expect(adjusted.targetBedHour == 1.0)
        #expect(adjusted.targetWakeHour == 9.0)
        #expect(adjusted.toleranceMinutes == 120)
    }

    @Test("Intermediate chronotype keeps default-like timing")
    func goalIntermediate() {
        let base = SleepGoal.generalHealthDefault
        let adjusted = ChronotypeEngine.adjustedSleepGoal(base: base, chronotype: .intermediate)
        #expect(adjusted.targetBedHour == 23.0)
        #expect(adjusted.targetWakeHour == 7.0)
        #expect(adjusted.toleranceMinutes == 90)
    }

    @Test("Non-generalHealth mode goal is not adjusted")
    func shiftWorkNotAdjusted() {
        let shiftGoal = SleepGoal(
            mode: .shiftWork,
            targetBedHour: 8.0,
            targetWakeHour: 16.0,
            targetDuration: 8.0,
            toleranceMinutes: 60
        )
        let adjusted = ChronotypeEngine.adjustedSleepGoal(base: shiftGoal, chronotype: .definiteMorning)
        #expect(adjusted.targetBedHour == 8.0)
        #expect(adjusted.targetWakeHour == 16.0)
    }

    // MARK: - Chronotype range check

    @Test("Evening type bedtime at 01:00 is within range")
    func eveningInRange() {
        #expect(ChronotypeEngine.isWithinChronotypeRange(bedtime: 1.0, chronotype: .definiteEvening))
    }

    @Test("Morning type bedtime at 01:00 is NOT within range")
    func morningOutOfRange() {
        #expect(!ChronotypeEngine.isWithinChronotypeRange(bedtime: 1.0, chronotype: .definiteMorning))
    }

    @Test("Intermediate bedtime at 23:30 is within range")
    func intermediateInRange() {
        #expect(ChronotypeEngine.isWithinChronotypeRange(bedtime: 23.5, chronotype: .intermediate))
    }

    // MARK: - Chronotype properties

    @Test("All chronotypes have valid Tmin estimates")
    func tminEstimates() {
        for ct in Chronotype.allCases {
            #expect(ct.tminEstimate >= 2.0 && ct.tminEstimate <= 9.0,
                    "Tmin for \(ct.label) should be 2-9h, got \(ct.tminEstimate)")
        }
    }

    @Test("All chronotypes have emoji")
    func emojis() {
        for ct in Chronotype.allCases {
            #expect(!ct.emoji.isEmpty)
        }
    }

    @Test("Chronotype.from(score:) covers all valid scores")
    func allScoresCovered() {
        for score in 4...25 {
            let ct = Chronotype.from(score: score)
            #expect(Chronotype.allCases.contains(ct))
        }
    }
}
