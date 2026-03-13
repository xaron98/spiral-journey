import Foundation
import Testing
@testable import SpiralKit

@Suite("BiomarkerEstimation Tests")
struct BiomarkerTests {

    // MARK: - Helpers

    private func makeRecord(bedtime: Double, wakeup: Double, duration: Double) -> SleepRecord {
        SleepRecord(
            day: 0,
            date: Date(),
            isWeekend: false,
            bedtimeHour: bedtime,
            wakeupHour: wakeup,
            sleepDuration: duration,
            phases: [],
            hourlyActivity: (0..<24).map { h in
                let asleep = (bedtime > wakeup)
                    ? (Double(h) >= bedtime || Double(h) < wakeup)
                    : (Double(h) >= bedtime && Double(h) < wakeup)
                return HourlyActivity(hour: h, activity: asleep ? 0.05 : 0.95)
            },
            cosinor: .empty
        )
    }

    // MARK: - Legacy method regression

    @Test("Legacy estimate returns fixed Tmin at 4.0")
    func legacyTminFixed() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimate(from: record)
        let tmin = markers.first(where: { $0.id == "tempNadir" })
        #expect(tmin != nil)
        #expect(tmin!.hour == 4.0)
        #expect(tmin!.confidenceLow == nil)
        #expect(tmin!.confidenceHigh == nil)
    }

    @Test("Legacy estimate returns 4 biomarkers without confidence")
    func legacyNoConfidence() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimate(from: record)
        #expect(markers.count == 4)
        for m in markers {
            #expect(m.confidenceLow == nil)
            #expect(m.confidenceHigh == nil)
        }
    }

    // MARK: - Personalized method

    @Test("Personalized Tmin derived from sleep midpoint for typical sleeper")
    func personalizedTminTypical() {
        // Bedtime 23:00, wake 7:00, duration 8h → midpoint = 3:00 → Tmin = 4:00
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let tmin = markers.first(where: { $0.id == "tempNadir" })!
        #expect(tmin.hour > 3.5 && tmin.hour < 4.5) // ~4:00 ± tolerance
    }

    @Test("Personalized Tmin shifts for late sleeper")
    func personalizedTminLate() {
        // Bedtime 2:00, wake 10:00, duration 8h → midpoint = 6:00 → Tmin = 7:00
        let record = makeRecord(bedtime: 2, wakeup: 10, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let tmin = markers.first(where: { $0.id == "tempNadir" })!
        #expect(tmin.hour > 6.5 && tmin.hour < 7.5) // ~7:00
    }

    @Test("Personalized Tmin shifts for shift worker")
    func personalizedTminShiftWorker() {
        // Bedtime 6:00, wake 14:00, duration 8h → midpoint = 10:00 → Tmin = 11:00
        let record = makeRecord(bedtime: 6, wakeup: 14, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let tmin = markers.first(where: { $0.id == "tempNadir" })!
        #expect(tmin.hour > 10.5 && tmin.hour < 11.5) // ~11:00
    }

    @Test("All personalized biomarkers have confidence ranges")
    func personalizedHasConfidence() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        #expect(markers.count == 4)
        for m in markers {
            #expect(m.confidenceLow != nil, "Missing confidenceLow for \(m.id)")
            #expect(m.confidenceHigh != nil, "Missing confidenceHigh for \(m.id)")
        }
    }

    @Test("DLMO confidence range is ±1.5h")
    func dlmoConfidenceRange() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let dlmo = markers.first(where: { $0.id == "dlmo" })!
        // Range should span 3h total
        let span = rangeDifference(low: dlmo.confidenceLow!, high: dlmo.confidenceHigh!)
        #expect(abs(span - 3.0) < 0.01)
    }

    @Test("CAR confidence range is ±15min (0.5h total)")
    func carConfidenceRange() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let car = markers.first(where: { $0.id == "car" })!
        let span = rangeDifference(low: car.confidenceLow!, high: car.confidenceHigh!)
        #expect(abs(span - 0.5) < 0.01)
    }

    @Test("PLD anchored to Tmin + 10.5h")
    func pldAnchoredToTmin() {
        let record = makeRecord(bedtime: 23, wakeup: 7, duration: 8)
        let markers = BiomarkerEstimation.estimatePersonalized(from: record)
        let tmin = markers.first(where: { $0.id == "tempNadir" })!
        let pld = markers.first(where: { $0.id == "postLunchDip" })!
        let diff = mod24(pld.hour - tmin.hour)
        #expect(abs(diff - 10.5) < 0.01)
    }

    // MARK: - Helpers

    private func mod24(_ h: Double) -> Double {
        ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
    }

    /// Circular distance between two clock hours accounting for midnight wrap.
    private func rangeDifference(low: Double, high: Double) -> Double {
        let diff = high - low
        return diff >= 0 ? diff : diff + 24
    }
}
