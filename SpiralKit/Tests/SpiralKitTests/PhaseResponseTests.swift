import Testing
@testable import SpiralKit

@Suite("PhaseResponse")
struct PhaseResponseTests {

    @Test("Light PRC delays phase in evening (CT 10-20)")
    func testLightDelaysEvening() {
        // Evening light (CT15) should produce maximum delay
        let response = PhaseResponse.light(15)
        #expect(response < 0, "Evening light should delay (negative)")
        #expect(response < -1.0, "Max delay should be > 1h")
    }

    @Test("Light PRC advances phase in early morning")
    func testLightAdvancesMorning() {
        let response = PhaseResponse.light(23)
        #expect(response > 0, "Morning light should advance (positive)")
    }

    @Test("Melatonin is opposite of light")
    func testMelatoninOppositeLight() {
        for h in stride(from: 0.0, to: 24.0, by: 1.0) {
            let lightResp = PhaseResponse.light(h)
            let melatoninResp = PhaseResponse.melatonin(h)
            // melatonin = -light * 0.6
            #expect(abs(melatoninResp - (-lightResp * 0.6)) < 0.001)
        }
    }

    @Test("Caffeine only delays in evening (CT 14-22)")
    func testCaffeineEveningOnly() {
        let afternoon = PhaseResponse.caffeine(17)
        let morning = PhaseResponse.caffeine(8)
        #expect(afternoon < 0, "Afternoon caffeine should delay")
        #expect(morning == 0, "Morning caffeine has no effect")
    }

    @Test("Screen light is 30% of bright light")
    func testScreenLightScaling() {
        for h in stride(from: 0.0, to: 24.0, by: 2.0) {
            let screen = PhaseResponse.screenLight(h)
            let bright = PhaseResponse.light(h)
            #expect(abs(screen - bright * 0.3) < 0.001)
        }
    }

    @Test("All PRC models present in registry")
    func testAllModelsPresent() {
        for eventType in EventType.allCases where eventType.isManuallyLoggable {
            #expect(PhaseResponse.models[eventType] != nil, "Missing model for \(eventType)")
        }
    }

    @Test("Impulse response decays over time")
    func testImpulseDecay() {
        let day0 = PhaseResponse.impulseResponse(eventType: .light, circadianHour: 15, daysForward: 0)
        let day1 = PhaseResponse.impulseResponse(eventType: .light, circadianHour: 15, daysForward: 1)
        let day6 = PhaseResponse.impulseResponse(eventType: .light, circadianHour: 15, daysForward: 6)

        #expect(abs(day0) > abs(day1), "Response should decay over days")
        #expect(day6 == 0, "Past maxDays should be 0")
    }

    @Test("Curve generates 24h of data")
    func testCurveLength() {
        let curve = PhaseResponse.curve(for: .light)
        #expect(curve.count == 96)   // 24h / 0.25 step = 96 points
    }
}
