import Testing
import Foundation
@testable import SpiralKit

@Suite("CircadianEvent Model")
struct CircadianEventTests {

    @Test("EventSource defaults to manual")
    func defaultSource() {
        let event = CircadianEvent(type: .caffeine, absoluteHour: 14.0)
        #expect(event.source == .manual)
    }

    @Test("EventSource can be set to healthKit")
    func healthKitSource() {
        let event = CircadianEvent(type: .exercise, absoluteHour: 17.0, source: .healthKit)
        #expect(event.source == .healthKit)
    }

    @Test("Encode/decode with source preserves value")
    func codableWithSource() throws {
        let event = CircadianEvent(type: .exercise, absoluteHour: 10.0, source: .healthKit)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CircadianEvent.self, from: data)
        #expect(decoded.source == .healthKit)
    }

    @Test("Decode without source field defaults to manual (backward compat)")
    func codableBackwardCompat() throws {
        // JSON without "source" key — simulates existing persisted data.
        // timestamp uses timeIntervalSinceReferenceDate (Swift's default Date encoding).
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","type":"caffeine","absoluteHour":14.0,"timestamp":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CircadianEvent.self, from: json)
        #expect(decoded.source == .manual)
        #expect(decoded.type == .caffeine)
    }

    @Test("highHR event type has correct properties")
    func highHRProperties() {
        let type = EventType.highHR
        #expect(type.label == "High Heart Rate")
        #expect(type.hexColor == "#ff6b6b")
        #expect(type.sfSymbol == "heart.fill")
        #expect(type.hasDuration == false)
    }

    @Test("highHR is not manually loggable")
    func highHRNotManuallyLoggable() {
        #expect(!EventType.highHR.isManuallyLoggable)
    }

    @Test("All other event types are manually loggable")
    func otherTypesManuallyLoggable() {
        let manualTypes: [EventType] = [.light, .exercise, .melatonin, .caffeine, .screenLight, .alcohol, .meal, .stress]
        for type in manualTypes {
            #expect(type.isManuallyLoggable, "\(type) should be manually loggable")
        }
    }
}
