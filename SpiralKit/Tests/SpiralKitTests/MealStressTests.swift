import Foundation
import Testing
@testable import SpiralKit

@Suite("Meal & Stress PRC Tests")
struct MealStressTests {

    // MARK: - Meal PRC

    @Test("Meal PRC advances in morning (CT 6-10)")
    func mealMorningAdvance() {
        let ct8 = PhaseResponse.meal(8.0)
        #expect(ct8 > 0, "Morning meal should advance phase, got \(ct8)")
    }

    @Test("Meal PRC delays in evening (CT 18-22)")
    func mealEveningDelay() {
        let ct20 = PhaseResponse.meal(20.0)
        #expect(ct20 < 0, "Evening meal should delay phase, got \(ct20)")
    }

    @Test("Meal PRC is zero outside active zones")
    func mealZeroOutside() {
        #expect(PhaseResponse.meal(0.0) == 0)
        #expect(PhaseResponse.meal(12.0) == 0)
        #expect(PhaseResponse.meal(15.0) == 0)
    }

    // MARK: - Stress PRC

    @Test("Stress PRC advances in morning (CT 4-10)")
    func stressMorningAdvance() {
        let ct7 = PhaseResponse.stress(7.0)
        #expect(ct7 > 0, "Morning stress should advance phase, got \(ct7)")
    }

    @Test("Stress PRC delays in evening (CT 16-23)")
    func stressEveningDelay() {
        let ct20 = PhaseResponse.stress(20.0)
        #expect(ct20 < 0, "Evening stress should delay phase, got \(ct20)")
    }

    @Test("Stress evening delay is stronger than morning advance")
    func stressAsymmetry() {
        let maxAdvance = PhaseResponse.stress(7.0)
        let maxDelay = abs(PhaseResponse.stress(19.5))
        #expect(maxDelay > maxAdvance, "Evening delay (\(maxDelay)) should exceed morning advance (\(maxAdvance))")
    }

    // MARK: - Model registry

    @Test("All PRC models present in registry including meal and stress")
    func allModelsPresent() {
        for eventType in EventType.allCases where eventType.isManuallyLoggable {
            #expect(PhaseResponse.models[eventType] != nil, "Missing PRC model for \(eventType.rawValue)")
        }
    }

    // MARK: - Regression: existing PRCs unchanged

    @Test("Light PRC still advances in early morning")
    func lightRegression() {
        let ct4 = PhaseResponse.light(4.0)
        #expect(ct4 > 0, "Light should still advance in early morning")
    }

    @Test("Caffeine PRC still delays in evening")
    func caffeineRegression() {
        let ct18 = PhaseResponse.caffeine(18.0)
        #expect(ct18 < 0, "Caffeine should still delay in evening")
    }

    @Test("Exercise PRC unchanged")
    func exerciseRegression() {
        // Exercise is zero during day (CT 4-12)
        #expect(PhaseResponse.exercise(8.0) == 0)
    }

    @Test("Melatonin PRC is still opposite of light")
    func melatoninRegression() {
        let light6 = PhaseResponse.light(6.0)
        let mel6 = PhaseResponse.melatonin(6.0)
        #expect(abs(mel6 + light6 * 0.6) < 0.001, "Melatonin should be -0.6 × light")
    }

    @Test("Screen light PRC is still 30% of light")
    func screenLightRegression() {
        let light15 = PhaseResponse.light(15.0)
        let screen15 = PhaseResponse.screenLight(15.0)
        #expect(abs(screen15 - light15 * 0.3) < 0.001, "Screen light should be 0.3 × light")
    }

    // MARK: - EventType enum

    @Test("EventType meal has correct properties")
    func mealEventType() {
        #expect(EventType.meal.label == "Meal")
        #expect(EventType.meal.hexColor == "#7cb342")
        #expect(EventType.meal.sfSymbol == "fork.knife")
    }

    @Test("EventType stress has correct properties")
    func stressEventType() {
        #expect(EventType.stress.label == "Stress")
        #expect(EventType.stress.hexColor == "#e57373")
        #expect(EventType.stress.sfSymbol == "brain.head.profile")
    }
}
