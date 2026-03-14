import Foundation
import Testing
@testable import SpiralKit

@Suite("HRV Analysis Tests")
struct HRVTests {

    // MARK: - Helpers

    private func makeHRV(daysAgo: Int, sdnn: Double) -> NightlyHRV {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return NightlyHRV(date: date, meanSDNN: sdnn, sampleCount: 5)
    }

    // MARK: - Trend detection

    @Test("Empty data returns stable trend")
    func emptyTrend() {
        #expect(HRVAnalysis.trend([]) == .stable)
    }

    @Test("One data point returns stable trend")
    func singlePointTrend() {
        #expect(HRVAnalysis.trend([makeHRV(daysAgo: 0, sdnn: 50)]) == .stable)
    }

    @Test("Rising SDNN values detect rising trend")
    func risingTrend() {
        let data = [
            makeHRV(daysAgo: 6, sdnn: 30),
            makeHRV(daysAgo: 5, sdnn: 35),
            makeHRV(daysAgo: 4, sdnn: 40),
            makeHRV(daysAgo: 3, sdnn: 45),
            makeHRV(daysAgo: 2, sdnn: 50),
            makeHRV(daysAgo: 1, sdnn: 55),
            makeHRV(daysAgo: 0, sdnn: 60)
        ]
        #expect(HRVAnalysis.trend(data) == .rising)
    }

    @Test("Falling SDNN values detect falling trend")
    func fallingTrend() {
        let data = [
            makeHRV(daysAgo: 6, sdnn: 70),
            makeHRV(daysAgo: 5, sdnn: 65),
            makeHRV(daysAgo: 4, sdnn: 60),
            makeHRV(daysAgo: 3, sdnn: 55),
            makeHRV(daysAgo: 2, sdnn: 50),
            makeHRV(daysAgo: 1, sdnn: 45),
            makeHRV(daysAgo: 0, sdnn: 40)
        ]
        #expect(HRVAnalysis.trend(data) == .falling)
    }

    @Test("Flat SDNN values detect stable trend")
    func stableTrend() {
        let data = [
            makeHRV(daysAgo: 4, sdnn: 50),
            makeHRV(daysAgo: 3, sdnn: 50),
            makeHRV(daysAgo: 2, sdnn: 51),
            makeHRV(daysAgo: 1, sdnn: 49),
            makeHRV(daysAgo: 0, sdnn: 50)
        ]
        #expect(HRVAnalysis.trend(data) == .stable)
    }

    // MARK: - Mean SDNN

    @Test("Mean SDNN calculation")
    func meanCalculation() {
        let data = [
            makeHRV(daysAgo: 2, sdnn: 40),
            makeHRV(daysAgo: 1, sdnn: 50),
            makeHRV(daysAgo: 0, sdnn: 60)
        ]
        #expect(HRVAnalysis.meanSDNN(data) == 50.0)
    }

    @Test("Mean SDNN of empty data is 0")
    func meanEmpty() {
        #expect(HRVAnalysis.meanSDNN([]) == 0)
    }

    // MARK: - Interpretation

    @Test("Low SDNN interpretation")
    func interpretLow() {
        #expect(HRVAnalysis.interpretation(meanSDNN: 15) == .low)
    }

    @Test("Below average SDNN interpretation")
    func interpretBelowAverage() {
        #expect(HRVAnalysis.interpretation(meanSDNN: 35) == .belowAverage)
    }

    @Test("Average SDNN interpretation")
    func interpretAverage() {
        #expect(HRVAnalysis.interpretation(meanSDNN: 75) == .average)
    }

    @Test("Above average SDNN interpretation")
    func interpretAboveAverage() {
        #expect(HRVAnalysis.interpretation(meanSDNN: 120) == .aboveAverage)
    }

    @Test("High SDNN interpretation")
    func interpretHigh() {
        #expect(HRVAnalysis.interpretation(meanSDNN: 160) == .high)
    }
}
