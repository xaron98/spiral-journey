import Foundation
import Testing
@testable import SpiralKit

@Suite("SpiralDistance Tests")
struct SpiralDistanceTests {

    // MARK: - Legacy method regression

    @Test("Legacy distance is symmetric")
    func legacySymmetric() {
        let d1 = SpiralDistance.distance(day1: 0, hour1: 6, day2: 3, hour2: 18)
        let d2 = SpiralDistance.distance(day1: 3, hour1: 18, day2: 0, hour2: 6)
        #expect(abs(d1 - d2) < 1e-10)
    }

    @Test("Legacy distance same point is zero")
    func legacySamePoint() {
        let d = SpiralDistance.distance(day1: 5, hour1: 12, day2: 5, hour2: 12)
        #expect(abs(d) < 1e-10)
    }

    @Test("Legacy distance returns expected value for known inputs")
    func legacyKnownValue() {
        // Pure radial: same hour, 10 days apart → angularDist=0, radialDist=10 → 0 + 10*0.1 = 1.0
        let d = SpiralDistance.distance(day1: 0, hour1: 0, day2: 10, hour2: 0)
        #expect(abs(d - 1.0) < 1e-10)
    }

    // MARK: - Euclidean distance

    @Test("Euclidean distance is symmetric")
    func euclideanSymmetric() {
        let d1 = SpiralDistance.euclideanDistance(day1: 1, hour1: 3, day2: 5, hour2: 15)
        let d2 = SpiralDistance.euclideanDistance(day1: 5, hour1: 15, day2: 1, hour2: 3)
        #expect(abs(d1 - d2) < 1e-10)
    }

    @Test("Euclidean distance same point is zero")
    func euclideanSamePoint() {
        let d = SpiralDistance.euclideanDistance(day1: 3, hour1: 8, day2: 3, hour2: 8)
        #expect(abs(d) < 1e-10)
    }

    @Test("Euclidean pure radial distance (same hour, different days)")
    func euclideanPureRadial() {
        // Same hour → angular component = 0 → d = √(α·Δn²) = √(1·5²) = 5
        let d = SpiralDistance.euclideanDistance(day1: 0, hour1: 12, day2: 5, hour2: 12)
        #expect(abs(d - 5.0) < 1e-10)
    }

    @Test("Euclidean pure angular distance (same day, different hours)")
    func euclideanPureAngular() {
        // Same day → radial = 0; 12h apart on 24h period → dtheta = π → angularNorm = 1.0
        // d = √(β·1²) = 1.0
        let d = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 0, hour2: 12)
        #expect(abs(d - 1.0) < 1e-10)
    }

    @Test("Euclidean angular wraps correctly (6h and 18h are 12h apart)")
    func euclideanAngularWrap() {
        // 6h and 18h: direct diff = 12h = π → angularNorm = 1.0
        let d1 = SpiralDistance.euclideanDistance(day1: 0, hour1: 6, day2: 0, hour2: 18)
        // 23h and 1h: direct diff = 22h, but shortest = 2h = π/6 → angularNorm = 1/6
        let d2 = SpiralDistance.euclideanDistance(day1: 0, hour1: 23, day2: 0, hour2: 1)
        #expect(d1 > d2, "12h angular gap should be larger than 2h angular gap")
    }

    @Test("Euclidean alpha weight scales radial component")
    func euclideanAlphaWeight() {
        // Pure radial, 3 days: d = √(α·9)
        let d1 = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 3, hour2: 0, alpha: 1.0, beta: 1.0)
        let d2 = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 3, hour2: 0, alpha: 4.0, beta: 1.0)
        #expect(abs(d1 - 3.0) < 1e-10)
        #expect(abs(d2 - 6.0) < 1e-10) // √(4·9) = 6
    }

    @Test("Euclidean beta weight scales angular component")
    func euclideanBetaWeight() {
        // Pure angular, 12h apart: angularNorm = 1.0, d = √(β·1)
        let d1 = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 0, hour2: 12, alpha: 1.0, beta: 1.0)
        let d2 = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 0, hour2: 12, alpha: 1.0, beta: 4.0)
        #expect(abs(d1 - 1.0) < 1e-10)
        #expect(abs(d2 - 2.0) < 1e-10) // √(4·1) = 2
    }

    @Test("Euclidean combined radial and angular")
    func euclideanCombined() {
        // 5 days apart, 12h apart → d = √(1·25 + 1·1) = √26
        let d = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 5, hour2: 12)
        #expect(abs(d - sqrt(26)) < 1e-10)
    }

    @Test("Euclidean triangle inequality holds")
    func euclideanTriangleInequality() {
        let dAB = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 3, hour2: 6)
        let dBC = SpiralDistance.euclideanDistance(day1: 3, hour1: 6, day2: 7, hour2: 20)
        let dAC = SpiralDistance.euclideanDistance(day1: 0, hour1: 0, day2: 7, hour2: 20)
        #expect(dAC <= dAB + dBC + 1e-10, "Triangle inequality must hold")
    }

    // MARK: - Sector quality heatmap regression

    @Test("Sector heatmap returns correct number of sectors")
    func sectorCount() {
        let records = (0..<7).map { day in
            SleepRecord(
                day: day, date: Date(), isWeekend: day % 7 >= 5,
                bedtimeHour: 23, wakeupHour: 7, sleepDuration: 8,
                phases: [],
                hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.5) },
                cosinor: .empty
            )
        }
        let sectors = SpiralDistance.sectorQualityHeatmap(records, numSectors: 24)
        #expect(sectors.count == 24)
    }
}
