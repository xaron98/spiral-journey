import Testing
import Foundation
@testable import SpiralKit

@Suite("HealthMarkerDetector")
struct HealthMarkerTests {

    // MARK: - Helpers

    private func makeRecord(
        day: Int,
        bedtime: Double = 23,
        wakeup: Double = 7,
        duration: Double = 8,
        phases: [PhaseInterval] = [],
        cosinorR2: Double = 0.5,
        driftMinutes: Double = 0
    ) -> SleepRecord {
        SleepRecord(
            day: day,
            date: Date(),
            isWeekend: day % 7 >= 5,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: duration,
            phases: phases,
            hourlyActivity: (0..<24).map { h in
                HourlyActivity(hour: h, activity: h >= Int(wakeup) && h < Int(bedtime) ? 0.95 : 0.05)
            },
            cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: cosinorR2),
            driftMinutes: driftMinutes
        )
    }

    private func makePhases(
        deep: Int = 4,
        rem: Int = 4,
        light: Int = 8,
        awake: Int = 0,
        startHour: Double = 23
    ) -> [PhaseInterval] {
        var phases: [PhaseInterval] = []
        var hour = startHour
        let step = 0.25 // 15-minute intervals

        for _ in 0..<deep {
            phases.append(PhaseInterval(hour: hour.truncatingRemainder(dividingBy: 24), phase: .deep, timestamp: hour))
            hour += step
        }
        for _ in 0..<rem {
            phases.append(PhaseInterval(hour: hour.truncatingRemainder(dividingBy: 24), phase: .rem, timestamp: hour))
            hour += step
        }
        for _ in 0..<light {
            phases.append(PhaseInterval(hour: hour.truncatingRemainder(dividingBy: 24), phase: .light, timestamp: hour))
            hour += step
        }
        for _ in 0..<awake {
            phases.append(PhaseInterval(hour: hour.truncatingRemainder(dividingBy: 24), phase: .awake, timestamp: hour))
            hour += step
        }
        return phases
    }

    // MARK: - Circadian Coherence

    @Test("Stable cosinor R² = 0.8 yields coherence ≈ 0.8")
    func testCircadianCoherence() {
        let records = (0..<14).map { makeRecord(day: $0, cosinorR2: 0.8) }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.circadianCoherence - 0.8) < 1e-10)
    }

    @Test("Mixed R² values yield correct mean")
    func testCircadianCoherenceMixed() {
        var records = (0..<7).map { makeRecord(day: $0, cosinorR2: 0.9) }
        records += (7..<14).map { makeRecord(day: $0, cosinorR2: 0.3) }
        let markers = HealthMarkerDetector.analyze(records: records)
        let expected = (0.9 * 7 + 0.3 * 7) / 14.0
        #expect(abs(markers.circadianCoherence - expected) < 1e-10)
    }

    // MARK: - Fragmentation

    @Test("Many awake phases produce high fragmentation")
    func testHighFragmentation() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 4, rem: 4, light: 4, awake: 8)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        // 8 awake / 10 = 0.8 per night
        #expect(abs(markers.fragmentationScore - 0.8) < 1e-10)
    }

    @Test("No awake phases produce zero fragmentation")
    func testZeroFragmentation() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 4, rem: 4, light: 8, awake: 0)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.fragmentationScore) < 1e-10)
    }

    @Test("Fragmentation capped at 1.0 when awake count >= 10")
    func testFragmentationCapped() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 2, rem: 2, light: 2, awake: 15)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.fragmentationScore - 1.0) < 1e-10)
    }

    // MARK: - REM Drift Slope

    @Test("No REM phases yields nil RDS and nil RCE")
    func testNoREMPhases() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 8, rem: 0, light: 8, awake: 0)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(markers.remDriftSlope == nil)
        #expect(markers.remClusterEntropy == nil)
    }

    @Test("Sufficient REM phases produce non-nil RDS")
    func testREMDriftSlope() {
        // 4 REM phases per night × 14 nights = 56 REM phases
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 4, rem: 4, light: 4, awake: 0, startHour: 23)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(markers.remDriftSlope != nil)
    }

    // MARK: - Homeostasis Balance

    @Test("Aligned C ≈ S produces low HB")
    func testLowHomeostasisBalance() {
        // Create points where c ≈ s
        let points = (0..<48).map { i in
            TwoProcessModel.TwoProcessPoint(day: i / 24, hour: i % 24, s: 0.5, c: 0.5, isAwake: true)
        }
        let records = (0..<14).map { makeRecord(day: $0) }
        let markers = HealthMarkerDetector.analyze(records: records, twoProcessPoints: points)
        #expect(abs(markers.homeostasisBalance) < 1e-10)
    }

    @Test("No two-process points defaults HB to 0.5")
    func testDefaultHomeostasisBalance() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let markers = HealthMarkerDetector.analyze(records: records, twoProcessPoints: nil)
        #expect(abs(markers.homeostasisBalance - 0.5) < 1e-10)
    }

    // MARK: - Helical Continuity

    @Test("No awake phases yield HCI = 1.0")
    func testPerfectContinuity() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 4, rem: 4, light: 8, awake: 0)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.helicalContinuity - 1.0) < 1e-10)
    }

    @Test("Half awake phases yield HCI = 0.5")
    func testHalfContinuity() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 2, rem: 2, light: 2, awake: 6)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        // 6 awake out of 12 total = 0.5 breaks → HCI = 1 - 0.5 = 0.5
        #expect(abs(markers.helicalContinuity - 0.5) < 1e-10)
    }

    // MARK: - Drift Severity

    @Test("Consistent drift magnitude yields correct severity")
    func testDriftSeverity() {
        let records = (0..<14).map { makeRecord(day: $0, driftMinutes: 10) }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.driftSeverity - 10.0) < 1e-10)
    }

    @Test("Negative drift uses absolute value")
    func testNegativeDrift() {
        let records = (0..<14).map { makeRecord(day: $0, driftMinutes: -20) }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.driftSeverity - 20.0) < 1e-10)
    }

    // MARK: - Alerts

    @Test("Low coherence generates urgent circadianAnarchy alert")
    func testCircadianAnarchyAlert() {
        let records = (0..<14).map { makeRecord(day: $0, cosinorR2: 0.1) }
        let markers = HealthMarkerDetector.analyze(records: records)
        let alert = markers.alerts.first { $0.type == .circadianAnarchy }
        #expect(alert != nil)
        #expect(alert?.severity == .urgent)
    }

    @Test("High fragmentation generates warning alert")
    func testHighFragmentationAlert() {
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 1, rem: 1, light: 1, awake: 8)
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records)
        let alert = markers.alerts.first { $0.type == .highFragmentation }
        #expect(alert != nil)
        #expect(alert?.severity == .warning)
    }

    @Test("Severe drift generates warning alert")
    func testSevereDriftAlert() {
        let records = (0..<14).map { makeRecord(day: $0, driftMinutes: 20) }
        let markers = HealthMarkerDetector.analyze(records: records)
        let alert = markers.alerts.first { $0.type == .severeDrift }
        #expect(alert != nil)
        #expect(alert?.severity == .warning)
    }

    @Test("High desynchrony generates warning alert")
    func testHighDesynchronyAlert() {
        let points = (0..<48).map { i in
            TwoProcessModel.TwoProcessPoint(day: i / 24, hour: i % 24, s: 0.1, c: 0.8, isAwake: true)
        }
        let records = (0..<14).map { makeRecord(day: $0) }
        let markers = HealthMarkerDetector.analyze(records: records, twoProcessPoints: points)
        let alert = markers.alerts.first { $0.type == .highDesynchrony }
        #expect(alert != nil)
        #expect(alert?.severity == .warning)
    }

    @Test("Healthy markers generate no alerts")
    func testNoAlerts() {
        let points = (0..<48).map { i in
            TwoProcessModel.TwoProcessPoint(day: i / 24, hour: i % 24, s: 0.5, c: 0.55, isAwake: true)
        }
        let records = (0..<14).map { day in
            makeRecord(
                day: day,
                phases: makePhases(deep: 4, rem: 4, light: 8, awake: 0),
                cosinorR2: 0.8,
                driftMinutes: 5
            )
        }
        let markers = HealthMarkerDetector.analyze(records: records, twoProcessPoints: points)
        #expect(markers.alerts.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Empty records produce empty markers")
    func testEmptyRecords() {
        let markers = HealthMarkerDetector.analyze(records: [])
        #expect(markers.circadianCoherence == 0)
        #expect(markers.homeostasisBalance == 0.5)
        #expect(markers.helicalContinuity == 1.0)
        #expect(markers.alerts.isEmpty)
    }

    @Test("More than 14 records uses only last 14")
    func testWindowTrimming() {
        // First 10 records have R² = 0.1, last 14 have R² = 0.9
        var records = (0..<10).map { makeRecord(day: $0, cosinorR2: 0.1) }
        records += (10..<24).map { makeRecord(day: $0, cosinorR2: 0.9) }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(abs(markers.circadianCoherence - 0.9) < 1e-10)
    }

    @Test("Paradoxical insomnia is always nil")
    func testParadoxicalInsomnia() {
        let records = (0..<14).map { makeRecord(day: $0) }
        let markers = HealthMarkerDetector.analyze(records: records)
        #expect(markers.paradoxicalInsomnia == nil)
    }
}
