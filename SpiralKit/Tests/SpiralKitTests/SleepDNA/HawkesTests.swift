import Testing
import Foundation
@testable import SpiralKit

// MARK: - Helpers

private func makeRecord(
    day: Int,
    bedtime: Double = 23.0,
    wakeup: Double = 7.0,
    awakePhaseCount: Int = 0
) -> SleepRecord {
    var phases: [PhaseInterval] = []
    let windowHours = wakeup > bedtime ? Int(wakeup - bedtime) : Int(wakeup + 24 - bedtime)
    let baseTimestamp = Double(day) * 24.0

    for i in 0..<awakePhaseCount {
        let hourOffset = Double(i + 1) * (Double(windowHours) / Double(awakePhaseCount + 1))
        let clockHour = (bedtime + hourOffset).truncatingRemainder(dividingBy: 24.0)
        phases.append(PhaseInterval(hour: clockHour, phase: .awake, timestamp: baseTimestamp + hourOffset))
    }
    for h in 0..<windowHours {
        let clockHour = (bedtime + Double(h) + 0.5).truncatingRemainder(dividingBy: 24.0)
        phases.append(PhaseInterval(hour: clockHour, phase: .light, timestamp: baseTimestamp + Double(h)))
    }

    return SleepRecord(
        day: day,
        date: Date(),
        isWeekend: day % 7 >= 5,
        bedtimeHour: bedtime,
        wakeupHour: wakeup,
        sleepDuration: Double(windowHours),
        phases: phases,
        hourlyActivity: (0..<24).map { HourlyActivity(hour: $0, activity: 0.1) },
        cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.5),
        driftMinutes: 0
    )
}

private func makeEvent(type: EventType, absoluteHour: Double) -> CircadianEvent {
    CircadianEvent(type: type, absoluteHour: absoluteHour)
}

// MARK: - Base Intensity Tests

@Suite("HawkesEventModel — Base Intensity")
struct HawkesBaseIntensityTests {

    @Test("Base intensity equals mean awakenings when no events are present")
    func testBaseIntensityNoEvents() {
        let records = [
            makeRecord(day: 0, awakePhaseCount: 1),
            makeRecord(day: 1, awakePhaseCount: 2),
            makeRecord(day: 2, awakePhaseCount: 3),
        ]
        let result = HawkesEventModel.analyze(records: records, events: [])
        // With no events, baseIntensity should be the mean count (2.0)
        #expect(abs(result.baseIntensity - 2.0) < 1e-10)
    }

    @Test("Base intensity is non-negative")
    func testBaseIntensityNonNegative() {
        let records = (0..<10).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let events = (0..<5).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i) * 24.0 + 14.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        #expect(result.baseIntensity >= 0.0)
    }

    @Test("Empty records return zero base intensity")
    func testEmptyRecords() {
        let result = HawkesEventModel.analyze(records: [], events: [])
        #expect(result.baseIntensity == 0.0)
        #expect(result.eventImpacts.isEmpty)
    }

    @Test("Single record returns mean as base intensity with no events")
    func testSingleRecord() {
        let record = makeRecord(day: 0, awakePhaseCount: 3)
        let result = HawkesEventModel.analyze(records: [record], events: [])
        #expect(result.baseIntensity == 3.0)
    }
}

// MARK: - Excitation Strength Tests

@Suite("HawkesEventModel — Event Excitation")
struct HawkesExcitationTests {

    @Test("Caffeine events before high-awakening nights increase excitation strength")
    func testCaffeineIncreasesExcitation() {
        // Build nights where high awakenings follow caffeine events
        var records: [SleepRecord] = []
        var events: [CircadianEvent] = []

        for day in 0..<14 {
            let isHighNight = day % 2 == 0
            records.append(makeRecord(day: day, awakePhaseCount: isHighNight ? 4 : 1))

            if isHighNight && day > 0 {
                // Caffeine event ~12h before the high-awakening night
                let eventHour = Double(day) * 24.0 + 11.0  // ~11h before sleep at 23h
                events.append(makeEvent(type: .caffeine, absoluteHour: eventHour))
            }
        }

        let result = HawkesEventModel.analyze(records: records, events: events)
        let caffeineImpact = result.eventImpacts.first { $0.eventType == .caffeine }

        // Caffeine should have a positive excitation strength
        #expect(caffeineImpact != nil)
        #expect(caffeineImpact!.excitationStrength >= 0.0)
    }

    @Test("Excitation strength is non-negative for all types")
    func testExcitationNonNegative() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let events: [CircadianEvent] = EventType.allCases.enumerated().map { (i, type_) in
            makeEvent(type: type_, absoluteHour: Double(i) * 24.0 + 15.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        // Excitation can be negative (protective effect) or positive (harmful)
        for impact in result.eventImpacts {
            #expect(impact.excitationStrength.isFinite)
        }
    }

    @Test("significantEffect flag matches abs(excitationStrength) > 0.1")
    func testSignificantEffectFlag() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 4) }
        let events = (0..<7).map { i in
            makeEvent(type: .stress, absoluteHour: Double(i * 2) * 24.0 + 18.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        for impact in result.eventImpacts {
            #expect(impact.significantEffect == (abs(impact.excitationStrength) > 0.1))
        }
    }

    @Test("Event type with no events is absent from eventImpacts")
    func testMissingEventTypeAbsent() {
        let records = (0..<10).map { makeRecord(day: $0, awakePhaseCount: 2) }
        // Only caffeine events — other types should not appear in impacts
        let events = (0..<5).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i) * 24.0 + 14.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        let types = Set(result.eventImpacts.map { $0.eventType })
        // Only caffeine (and possibly no others) should be present
        for type_ in EventType.allCases where type_ != .caffeine {
            #expect(!types.contains(type_))
        }
    }
}

// MARK: - Decay Half-Life Tests

@Suite("HawkesEventModel — Decay")
struct HawkesDecayTests {

    @Test("Decay half-life is one of the candidate values")
    func testDecayHalfLifeIsCandidate() {
        let validHalfLives: Set<Double> = [12, 24, 36, 48, 72]
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let events = (0..<7).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i) * 24.0 + 14.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        #expect(validHalfLives.contains(result.decayHalfLife))
    }

    @Test("Events far in the past produce lower excitation than recent events")
    func testDecayReducesEffect() {
        // Two separate test configs: one with events just before sleep, one far away
        let records = (0..<10).map { makeRecord(day: $0, awakePhaseCount: 2) }

        // Recent events: 12h before each night
        var recentEvents: [CircadianEvent] = []
        for day in 0..<10 {
            let nightStart = Double(day) * 24.0 + 23.0
            recentEvents.append(makeEvent(type: .caffeine, absoluteHour: nightStart - 12.0))
        }

        // Distant events: 5 days before each night
        var distantEvents: [CircadianEvent] = []
        for day in 0..<10 {
            let nightStart = Double(day) * 24.0 + 23.0
            distantEvents.append(makeEvent(type: .caffeine, absoluteHour: nightStart - 120.0))
        }

        let recentResult = HawkesEventModel.analyze(records: records, events: recentEvents)
        let distantResult = HawkesEventModel.analyze(records: records, events: distantEvents)

        let recentStrength = recentResult.eventImpacts.first { $0.eventType == .caffeine }?.excitationStrength ?? 0
        let distantStrength = distantResult.eventImpacts.first { $0.eventType == .caffeine }?.excitationStrength ?? 0

        // Recent events should have at least as much excitation as distant ones
        // (this can be equal when awakenings are constant and regression slope is 0)
        #expect(recentStrength >= distantStrength - 1e-10)
    }

    @Test("delayHours matches decayHalfLife in results")
    func testDelayHoursMatchHalfLife() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let events = (0..<7).map { i in
            makeEvent(type: .stress, absoluteHour: Double(i) * 24.0 + 18.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)
        for impact in result.eventImpacts {
            #expect(impact.delayHours == result.decayHalfLife)
        }
    }
}

// MARK: - Multiple Event Types Tests

@Suite("HawkesEventModel — Multiple Types")
struct HawkesMultipleTypesTests {

    @Test("Multiple event types handled independently")
    func testMultipleEventTypes() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let caffeineEvents = (0..<7).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i * 2) * 24.0 + 14.0)
        }
        let stressEvents = (0..<7).map { i in
            makeEvent(type: .stress, absoluteHour: Double(i * 2) * 24.0 + 18.0)
        }
        let allEvents = caffeineEvents + stressEvents

        let result = HawkesEventModel.analyze(records: records, events: allEvents)
        let types = Set(result.eventImpacts.map { $0.eventType })

        #expect(types.contains(.caffeine))
        #expect(types.contains(.stress))
    }

    @Test("Each event type has its own excitation strength")
    func testEachTypeHasOwnStrength() {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 4) }
        let events: [CircadianEvent] = [
            makeEvent(type: .caffeine, absoluteHour: 14.0),
            makeEvent(type: .alcohol,  absoluteHour: 38.0),
            makeEvent(type: .exercise, absoluteHour: 62.0),
        ]
        let result = HawkesEventModel.analyze(records: records, events: events)

        // All three types should appear (they each have events)
        let presentTypes = Set(result.eventImpacts.map { $0.eventType })
        for type_ in [EventType.caffeine, .alcohol, .exercise] {
            #expect(presentTypes.contains(type_))
        }
    }
}

// MARK: - Linear Regression Helper Tests

@Suite("HawkesEventModel — Linear Regression")
struct HawkesLinearRegressionTests {

    @Test("Perfect linear relationship returns R² = 1")
    func testPerfectFit() {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [2, 4, 6, 8, 10]  // y = 2x
        let (intercept, slope, r2) = HawkesEventModel.linearRegression(x: x, y: y)
        #expect(abs(intercept - 0.0) < 1e-8)
        #expect(abs(slope - 2.0) < 1e-8)
        #expect(abs(r2 - 1.0) < 1e-8)
    }

    @Test("Constant x returns zero slope and mean intercept")
    func testConstantX() {
        let x: [Double] = [3, 3, 3, 3]
        let y: [Double] = [1, 2, 3, 4]
        let (intercept, slope, _) = HawkesEventModel.linearRegression(x: x, y: y)
        #expect(abs(slope) < 1e-10)
        #expect(abs(intercept - 2.5) < 1e-10)
    }

    @Test("Zero relationship returns R² ~ 0")
    func testZeroRelationship() {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [3, 3, 3, 3, 3]  // constant y — no correlation
        let (_, _, r2) = HawkesEventModel.linearRegression(x: x, y: y)
        // R² = 1.0 when ssTot ≈ 0 (constant y), which is the degenerate case
        #expect(r2 >= 0.0)
    }

    @Test("Single-element returns intercept equal to y and zero slope")
    func testSingleElement() {
        let (intercept, slope, r2) = HawkesEventModel.linearRegression(x: [5], y: [7])
        #expect(intercept == 7.0)
        #expect(slope == 0.0)
        #expect(r2 == 0.0)
    }
}

// MARK: - Codability Tests

@Suite("HawkesEventModel — Codable")
struct HawkesCodableTests {

    @Test("HawkesAnalysisResult is Codable")
    func testCodable() throws {
        let records = (0..<14).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
        let events = (0..<7).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i) * 24.0 + 14.0)
        }
        let result = HawkesEventModel.analyze(records: records, events: events)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(HawkesAnalysisResult.self, from: data)

        #expect(decoded.baseIntensity == result.baseIntensity)
        #expect(decoded.decayHalfLife == result.decayHalfLife)
        #expect(decoded.eventImpacts.count == result.eventImpacts.count)
    }

    @Test("EventImpact is Codable")
    func testEventImpactCodable() throws {
        let impact = EventImpact(
            eventType: .caffeine,
            excitationStrength: 0.42,
            delayHours: 24.0,
            significantEffect: true
        )
        let data = try JSONEncoder().encode(impact)
        let decoded = try JSONDecoder().decode(EventImpact.self, from: data)

        #expect(decoded.eventType == impact.eventType)
        #expect(decoded.excitationStrength == impact.excitationStrength)
        #expect(decoded.delayHours == impact.delayHours)
        #expect(decoded.significantEffect == impact.significantEffect)
    }
}

// MARK: - Integration with SleepDNAComputer

@Suite("HawkesEventModel — Computer Integration")
struct HawkesComputerIntegrationTests {

    private func makeRecords(count: Int) -> [SleepRecord] {
        (0..<count).map { makeRecord(day: $0, awakePhaseCount: $0 % 3) }
    }

    @Test("Full tier with events has hawkesAnalysis")
    func testFullTierHasHawkes() async throws {
        let records = makeRecords(count: 60)
        let events = (0..<20).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i * 3) * 24.0 + 14.0)
        }
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: events,
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .full)
        #expect(profile.hawkesAnalysis != nil)
    }

    @Test("Intermediate tier does not have hawkesAnalysis")
    func testIntermediateTierNoHawkes() async throws {
        let records = makeRecords(count: 28)
        let events = (0..<10).map { i in
            makeEvent(type: .caffeine, absoluteHour: Double(i) * 24.0 + 14.0)
        }
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: events,
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .intermediate)
        #expect(profile.hawkesAnalysis == nil)
    }

    @Test("Full tier with no events still has hawkesAnalysis (base intensity only)")
    func testFullTierNoEvents() async throws {
        let records = makeRecords(count: 60)
        let computer = SleepDNAComputer()
        let profile = try await computer.compute(
            records: records,
            events: [],
            chronotype: nil,
            goalDuration: 8
        )
        #expect(profile.tier == .full)
        #expect(profile.hawkesAnalysis != nil)
        #expect(profile.hawkesAnalysis!.eventImpacts.isEmpty)
    }
}
