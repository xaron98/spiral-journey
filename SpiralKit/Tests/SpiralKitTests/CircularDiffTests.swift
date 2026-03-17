import Testing
import Foundation
@testable import SpiralKit

@Suite("CircularTimeDiff")
struct CircularDiffTests {

    // MARK: - Pure function tests

    @Test("Same time gives zero diff")
    func testSameTime() {
        #expect(circularTimeDiff(7.0, 7.0) == 0)
        #expect(circularTimeDiff(0.0, 0.0) == 0)
        #expect(circularTimeDiff(23.5, 23.5) == 0)
    }

    @Test("Small positive difference")
    func testSmallPositive() {
        // predicted 7.5, actual 7.0 → predicted 0.5h too late
        let d = circularTimeDiff(7.5, 7.0)
        #expect(abs(d - 0.5) < 0.001)
    }

    @Test("Small negative difference")
    func testSmallNegative() {
        // predicted 6.5, actual 7.0 → predicted 0.5h too early
        let d = circularTimeDiff(6.5, 7.0)
        #expect(abs(d - (-0.5)) < 0.001)
    }

    @Test("Wrap around midnight: 23.5 vs 0.5 is -1h, not +23h")
    func testMidnightWrapNearValues() {
        // predicted 23.5, actual 0.5 → predicted 1h too early (wraps back)
        let d = circularTimeDiff(23.5, 0.5)
        #expect(abs(d - (-1.0)) < 0.001)
    }

    @Test("Wrap around midnight: 0.5 vs 23.5 is +1h, not -23h")
    func testMidnightWrapForward() {
        // predicted 0.5, actual 23.5 → predicted 1h too late
        let d = circularTimeDiff(0.5, 23.5)
        #expect(abs(d - 1.0) < 0.001)
    }

    @Test("Exactly 12 hours apart stays positive")
    func testTwelveHours() {
        let d = circularTimeDiff(18.0, 6.0)
        #expect(abs(d - 12.0) < 0.001 || abs(d - (-12.0)) < 0.001)
    }

    @Test("Bedtime wrap: 23h predicted vs 1h actual is -2h")
    func testBedtimeWrap() {
        let d = circularTimeDiff(23.0, 1.0)
        #expect(abs(d - (-2.0)) < 0.001)
    }

    @Test("Wake at 0.25 predicted vs 23.75 actual is +0.5h")
    func testWakeNearMidnight() {
        let d = circularTimeDiff(0.25, 23.75)
        #expect(abs(d - 0.5) < 0.001)
    }

    // MARK: - Integration: evaluate() uses circular diff for wake

    @Test("evaluate() uses circular diff for wake time across midnight")
    func testEvaluateWakeCircular() {
        let output = PredictionOutput(
            predictedBedtimeHour: 23.0,
            predictedWakeHour: 7.25,
            predictedDuration: 8.0,
            confidence: .medium,
            targetDate: Date()
        )
        let input = PredictionInput()
        var result = PredictionResult(prediction: output, input: input)

        // Actual wake at 6.5 → error should be +0.75h = +45 min
        result.evaluate(bedtime: 23.0, wake: 6.5, duration: 8.0)

        #expect(result.errorWakeMinutes != nil)
        #expect(abs(result.errorWakeMinutes! - 45.0) < 0.1)
    }

    @Test("evaluate() wake error across midnight gives small error, not ~23h")
    func testEvaluateWakeMidnightBug() {
        let output = PredictionOutput(
            predictedBedtimeHour: 23.0,
            predictedWakeHour: 0.25,   // predicted wake just after midnight
            predictedDuration: 1.0,
            confidence: .low,
            targetDate: Date()
        )
        let input = PredictionInput()
        var result = PredictionResult(prediction: output, input: input)

        // Actual wake at 23.75 (just before midnight) → should be +0.5h = +30min
        result.evaluate(bedtime: 22.5, wake: 23.75, duration: 1.0)

        #expect(result.errorWakeMinutes != nil)
        // Before fix this would be (0.25 - 23.75) * 60 = -1410 min
        // After fix this should be +30 min
        #expect(abs(result.errorWakeMinutes! - 30.0) < 0.1)
    }

    @Test("evaluate() bedtime still uses circular diff correctly")
    func testEvaluateBedtimeCircular() {
        let output = PredictionOutput(
            predictedBedtimeHour: 23.5,
            predictedWakeHour: 7.0,
            predictedDuration: 7.5,
            confidence: .high,
            targetDate: Date()
        )
        let input = PredictionInput()
        var result = PredictionResult(prediction: output, input: input)

        // Actual bedtime at 0.5 → diff should be -1h = -60 min
        result.evaluate(bedtime: 0.5, wake: 7.0, duration: 7.5)

        #expect(result.errorBedtimeMinutes != nil)
        #expect(abs(result.errorBedtimeMinutes! - (-60.0)) < 0.1)
    }
}
