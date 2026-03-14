import Testing
@testable import SpiralKit
import Foundation

@Suite("DisorderDetection Tests")
struct DisorderDetectionTests {

    // MARK: - Helpers

    /// Create a SleepRecord with the specified acrophase (and optional amplitude/R²).
    private func makeRecord(
        day: Int,
        acrophase: Double,
        amplitude: Double = 0.3,
        r2: Double = 0.8
    ) -> SleepRecord {
        SleepRecord(
            day: day,
            date: Date(),
            isWeekend: day % 7 >= 5,
            bedtimeHour: (acrophase - 8).truncatingRemainder(dividingBy: 24),
            wakeupHour: acrophase - 8 + 8,
            sleepDuration: 8,
            phases: [],
            hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
            cosinor: CosinorResult(
                mesor: 0.5, amplitude: amplitude, acrophase: acrophase,
                period: 24, r2: r2
            )
        )
    }

    // MARK: - Basic Tests

    @Test("Fewer than 7 records returns empty")
    func insufficientData() {
        let records = (0..<5).map { makeRecord(day: $0, acrophase: 15.0) }
        let result = DisorderDetection.detect(from: records)
        #expect(result.isEmpty)
    }

    @Test("Normal stable pattern returns 'Normal' signature")
    func normalPattern() {
        let records = (0..<14).map { makeRecord(day: $0, acrophase: 15.0) }
        let result = DisorderDetection.detect(from: records)
        #expect(!result.isEmpty)
        #expect(result[0].id == "normal")
    }

    @Test("Late acrophase (>17h) with low variability → DSWPD")
    func dswpdDetected() {
        let records = (0..<14).map { makeRecord(day: $0, acrophase: 19.0) }
        let result = DisorderDetection.detect(from: records)
        let dswpd = result.first { $0.id == "dswpd" }
        #expect(dswpd != nil, "Should detect DSWPD pattern")
    }

    @Test("Early acrophase (<12h) with low variability → ASWPD")
    func aswpdDetected() {
        let records = (0..<14).map { makeRecord(day: $0, acrophase: 9.0) }
        let result = DisorderDetection.detect(from: records)
        let aswpd = result.first { $0.id == "aswpd" }
        #expect(aswpd != nil, "Should detect ASWPD pattern")
    }

    @Test("High variability + low amplitude + low R² → ISWRD")
    func iswrdDetected() {
        // Spread acrophases widely with low amplitude and R²
        let acrophases = [2.0, 14.0, 8.0, 20.0, 5.0, 17.0, 11.0, 23.0, 3.0, 15.0]
        let records = acrophases.enumerated().map {
            makeRecord(day: $0.offset, acrophase: $0.element, amplitude: 0.05, r2: 0.15)
        }
        let result = DisorderDetection.detect(from: records)
        let iswrd = result.first { $0.id == "iswrd" }
        #expect(iswrd != nil, "Should detect ISWRD pattern")
    }

    @Test("Progressive drift → N24SWD")
    func n24swdDetected() {
        // Acrophase drifts by ~0.3h/day (clearly >0.15 threshold)
        let records = (0..<14).map {
            makeRecord(day: $0, acrophase: 14.0 + Double($0) * 0.3, r2: 0.7)
        }
        let result = DisorderDetection.detect(from: records)
        let n24 = result.first { $0.id == "n24swd" }
        #expect(n24 != nil, "Should detect N24SWD drift")
    }

    // MARK: - Circular Arithmetic Tests

    @Test("Acrophases crossing midnight compute correct circular mean")
    func circularMeanMidnight() {
        // Half the records at 23h, half at 1h — circular mean should be ~0h (midnight)
        var records: [SleepRecord] = []
        for i in 0..<7 {
            records.append(makeRecord(day: i, acrophase: 23.0))
        }
        for i in 7..<14 {
            records.append(makeRecord(day: i, acrophase: 1.0))
        }
        let result = DisorderDetection.detect(from: records)
        // Should NOT detect DSWPD (meanAcrophase ~0h, not >17h)
        // and should NOT detect ASWPD (meanAcrophase ~0h, not <12h strictly in the wrong way)
        let dswpd = result.first { $0.id == "dswpd" }
        // With linear mean: (23*7 + 1*7)/14 = 12.0 — wrong (would be neither)
        // With circular mean: ~0h or ~24h — should not trigger DSWPD
        #expect(dswpd == nil, "Midnight-crossing acrophases should NOT trigger DSWPD")
    }

    @Test("Constant midnight acrophases have low circular std")
    func midnightLowStd() {
        // All acrophases at 23.5h — should have very low variability
        let records = (0..<14).map { makeRecord(day: $0, acrophase: 23.5) }
        let result = DisorderDetection.detect(from: records)
        // Should NOT detect ISWRD (high variability disorder)
        let iswrd = result.first { $0.id == "iswrd" }
        #expect(iswrd == nil, "Constant 23.5h acrophases should have low std, no ISWRD")
    }

    @Test("Drift detection works across midnight boundary")
    func driftAcrossMidnight() {
        // Acrophase starts at 22h and drifts +0.3h/day, crossing midnight
        let records = (0..<14).map {
            let acro = (22.0 + Double($0) * 0.3).truncatingRemainder(dividingBy: 24.0)
            return makeRecord(day: $0, acrophase: acro, r2: 0.7)
        }
        let result = DisorderDetection.detect(from: records)
        let n24 = result.first { $0.id == "n24swd" }
        // With unwrapped regression, the slope should be detected correctly
        #expect(n24 != nil, "Should detect progressive drift across midnight")
    }

    @Test("All signatures have non-empty labels and descriptions")
    func signatureFields() {
        let records = (0..<14).map { makeRecord(day: $0, acrophase: 15.0) }
        let result = DisorderDetection.detect(from: records)
        for sig in result {
            #expect(!sig.id.isEmpty)
            #expect(!sig.label.isEmpty)
            #expect(!sig.fullLabel.isEmpty)
            #expect(!sig.description.isEmpty)
            #expect(!sig.hexColor.isEmpty)
            #expect(sig.confidence >= 0 && sig.confidence <= 1)
        }
    }
}
