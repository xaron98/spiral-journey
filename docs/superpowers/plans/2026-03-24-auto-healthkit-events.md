# Auto HealthKit Events Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-populate workouts, caffeine, and high heart rate alerts from HealthKit as CircadianEvents on the spiral, deduplicated against manual events.

**Architecture:** Add `EventSource` + `highHR` to the SpiralKit model, add 3 fetch methods to HealthKitManager, add import/dedup logic to SpiralStore, filter `highHR` from manual logging UI.

**Tech Stack:** Swift, SpiralKit, HealthKit, SwiftUI

**Spec:** `docs/superpowers/specs/2026-03-24-auto-healthkit-events-design.md`

**Build command:** `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

**SpiralKit test command:** `cd "/Users/xaron/Desktop/spiral journey project/SpiralKit" && swift test`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `SpiralKit/Sources/SpiralKit/Models/CircadianEvent.swift` | Add `EventSource`, `source` field, `highHR` type, `isManuallyLoggable`, custom Codable |
| Create | `SpiralKit/Tests/SpiralKitTests/CircadianEventTests.swift` | Tests for new model features |
| Modify | `spiral journey project/Services/HealthKitManager.swift` | Add auth types + fetchWorkouts + fetchCaffeineIntake + fetchHighHRAlerts |
| Modify | `spiral journey project/Services/SpiralStore.swift` | importHealthKitEvents(), dedup, deletedAutoEventKeys, skip CloudKit for auto |
| Modify | `spiral journey project/Views/Panels/EventPanelView.swift` | Filter isManuallyLoggable, show ⌚ for .healthKit events |
| Modify | `spiral journey project/Views/Tabs/SpiralTab.swift` | Filter isManuallyLoggable in event grid |
| Modify | `spiral journey project/Views/Charts/PRCChartView.swift` | Filter isManuallyLoggable in PRC legend |
| Modify | `Spiral Watch App Watch App/WatchEventLogView.swift` | Filter isManuallyLoggable in Watch event grid |
| Modify | `SpiralKit/Tests/SpiralKitTests/PhaseResponseTests.swift` | Filter isManuallyLoggable in allCases assertion |
| Modify | `SpiralKit/Tests/SpiralKitTests/MealStressTests.swift` | Filter isManuallyLoggable in allCases assertion |
| Modify | `spiral journey project/Localizable.xcstrings` | Add highHR + auto-event strings |

---

## Chunk 1: Model Changes + Tests

### Task 1: Add EventSource, source field, and highHR to CircadianEvent

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Models/CircadianEvent.swift`
- Create: `SpiralKit/Tests/SpiralKitTests/CircadianEventTests.swift`

- [ ] **Step 1: Write tests for the new model features**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/xaron/Desktop/spiral journey project/SpiralKit" && swift test --filter CircadianEventTests`
Expected: FAIL — `EventSource` not found, `source` not a member, `highHR` not found

- [ ] **Step 3: Implement model changes**

In `CircadianEvent.swift`:

**a) Add EventSource enum** (before `EventType`):
```swift
/// Source of a circadian event — manual user entry or automatic HealthKit import.
public enum EventSource: String, Codable, Sendable {
    case manual
    case healthKit
}
```

**b) Add highHR case to EventType** (after `stress`):
```swift
case highHR = "highHR"
```

**c) Add highHR to all switch statements in EventType:**
- `label`: `case .highHR: return "High Heart Rate"`
- `hexColor`: `case .highHR: return "#ff6b6b"`
- `sfSymbol`: `case .highHR: return "heart.fill"`
- `hasDuration`: `case .caffeine, .melatonin, .alcohol, .stress, .highHR: return false`

**d) Add isManuallyLoggable:**
```swift
/// Whether this event type can be logged manually by the user.
public var isManuallyLoggable: Bool {
    self != .highHR
}
```

**e) Add source field to CircadianEvent struct:**
```swift
public var source: EventSource
```

**f) Update init:**
```swift
public init(
    id: UUID = UUID(),
    type: EventType,
    absoluteHour: Double,
    timestamp: Date = Date(),
    note: String? = nil,
    durationHours: Double? = nil,
    source: EventSource = .manual
) {
    self.id = id
    self.type = type
    self.absoluteHour = absoluteHour
    self.timestamp = timestamp
    self.note = note
    self.durationHours = durationHours
    self.source = source
}
```

**g) Add custom Codable** (replace synthesized):
```swift
private enum CodingKeys: String, CodingKey {
    case id, type, absoluteHour, timestamp, note, durationHours, source
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    type = try container.decode(EventType.self, forKey: .type)
    absoluteHour = try container.decode(Double.self, forKey: .absoluteHour)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    note = try container.decodeIfPresent(String.self, forKey: .note)
    durationHours = try container.decodeIfPresent(Double.self, forKey: .durationHours)
    source = try container.decodeIfPresent(EventSource.self, forKey: .source) ?? .manual
}
```

- [ ] **Step 4: Run tests**

Run: `cd "/Users/xaron/Desktop/spiral journey project/SpiralKit" && swift test --filter CircadianEventTests`
Expected: ALL PASS

- [ ] **Step 5: Run full SpiralKit suite**

Run: `cd "/Users/xaron/Desktop/spiral journey project/SpiralKit" && swift test`
Expected: ALL PASS (502+ tests)

---

## Chunk 2: HealthKit Fetch Methods

### Task 2: Add new HealthKit types and fetch methods

**Files:**
- Modify: `spiral journey project/Services/HealthKitManager.swift`

- [ ] **Step 1: Add new types to fitnessReadTypes**

In the `fitnessReadTypes` computed property (around line 22-43), add inside the `var types: Set<HKObjectType>` block:

```swift
HKQuantityType(.dietaryCaffeine),
```

And add to the types set (not inside the iOS 17 check):
```swift
HKCategoryType(.highHeartRateEvent),
```

- [ ] **Step 2: Add WorkoutEvent and fetchWorkouts**

Add near the other fetch methods (after `fetchMenstrualFlow`):

```swift
// MARK: - Auto-Event Fetch Methods

struct WorkoutEvent {
    let startDate: Date
    let endDate: Date
    let durationHours: Double
    let workoutType: HKWorkoutActivityType
}

func fetchWorkouts(for date: Date) async -> [WorkoutEvent] {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKWorkoutType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            let workouts = (samples as? [HKWorkout])?.map { w in
                WorkoutEvent(
                    startDate: w.startDate,
                    endDate: w.endDate,
                    durationHours: w.duration / 3600.0,
                    workoutType: w.workoutActivityType
                )
            } ?? []
            continuation.resume(returning: workouts)
        }
        store.execute(query)
    }
}
```

- [ ] **Step 3: Add CaffeineEvent and fetchCaffeineIntake**

```swift
struct CaffeineEvent {
    let date: Date
    let milligrams: Double
}

func fetchCaffeineIntake(for date: Date) async -> [CaffeineEvent] {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    let caffeineType = HKQuantityType(.dietaryCaffeine)

    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: caffeineType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            let events = (samples as? [HKQuantitySample])?.map { s in
                CaffeineEvent(
                    date: s.startDate,
                    milligrams: s.quantity.doubleValue(for: .gramUnit(with: .milli))
                )
            } ?? []
            continuation.resume(returning: events)
        }
        store.execute(query)
    }
}
```

- [ ] **Step 4: Add fetchHighHRAlerts**

```swift
func fetchHighHRAlerts(for date: Date, threshold: Double = 120) async -> [Date] {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

    // Primary: Apple Watch system high HR alerts
    let systemAlerts = await fetchSystemHighHRAlerts(predicate: predicate)
    if !systemAlerts.isEmpty { return systemAlerts }

    // Fallback: manual HR sample filtering (no system alerts available)
    return await fetchManualHighHRAlerts(predicate: predicate, for: date, threshold: threshold)
}

private func fetchSystemHighHRAlerts(predicate: NSPredicate) async -> [Date] {
    let hrEventType = HKCategoryType(.highHeartRateEvent)

    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: hrEventType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            let dates = (samples as? [HKCategorySample])?.map(\.startDate) ?? []
            continuation.resume(returning: dates)
        }
        store.execute(query)
    }
}

private func fetchManualHighHRAlerts(predicate: NSPredicate, for date: Date, threshold: Double) async -> [Date] {
    // Get workouts to exclude exercise periods
    let workouts = await fetchWorkouts(for: date)
    let workoutRanges = workouts.map { ($0.startDate, $0.endDate) }

    let hrType = HKQuantityType(.heartRate)

    let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
        }
        store.execute(query)
    }

    // Filter: HR > threshold AND not during workout
    let highSamples = samples.filter { sample in
        let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        guard bpm > threshold else { return false }
        // Exclude samples during workouts
        let t = sample.startDate
        return !workoutRanges.contains { start, end in t >= start && t <= end }
    }

    // Cluster consecutive high-HR samples (within 5 min) → single alert at peak
    return clusterAlerts(highSamples)
}

private func clusterAlerts(_ samples: [HKQuantitySample]) -> [Date] {
    guard !samples.isEmpty else { return [] }
    var clusters: [[HKQuantitySample]] = [[samples[0]]]
    for i in 1..<samples.count {
        let gap = samples[i].startDate.timeIntervalSince(samples[i-1].startDate)
        if gap <= 300 { // 5 minutes
            clusters[clusters.count - 1].append(samples[i])
        } else {
            clusters.append([samples[i]])
        }
    }
    // Return the timestamp of the peak HR in each cluster
    return clusters.compactMap { cluster in
        cluster.max(by: {
            $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) <
            $1.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        })?.startDate
    }
}

```

**Note:** `fetchHighHRAlerts` accepts a `threshold` parameter (default 120). SpiralStore passes the personalized threshold (`restingHR + 40`) when calling.

- [ ] **Step 5: Build the app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

---

## Chunk 3: SpiralStore Integration

### Task 3: Import logic, dedup, deleted tracking, CloudKit skip

**Files:**
- Modify: `spiral journey project/Services/SpiralStore.swift`

- [ ] **Step 1: Add absoluteHour helper**

Add near the other private helpers:

```swift
/// Convert a Date to absoluteHour (hours since startDate).
private func absoluteHour(from date: Date) -> Double {
    date.timeIntervalSince(startDate) / 3600.0
}
```

- [ ] **Step 2: Add deletedAutoEventKeys with persistence**

Add properties near the other stored properties:

```swift
private static let deletedAutoEventsKey = "spiral-journey-deleted-auto-events"

private(set) var deletedAutoEventKeys: Set<String> = [] {
    didSet {
        if let data = try? JSONEncoder().encode(Array(deletedAutoEventKeys)) {
            sharedDefaults.set(data, forKey: Self.deletedAutoEventsKey)
        }
    }
}

private func autoEventKey(_ event: CircadianEvent) -> String {
    "\(event.type.rawValue)|\(Int(event.timestamp.timeIntervalSince1970))"
}

private func isDeletedAutoEvent(_ event: CircadianEvent) -> Bool {
    deletedAutoEventKeys.contains(autoEventKey(event))
}
```

In `load()` (or `init`), restore:
```swift
if let data = sharedDefaults.data(forKey: Self.deletedAutoEventsKey),
   let keys = try? JSONDecoder().decode([String].self, from: data) {
    deletedAutoEventKeys = Set(keys)
}
```

- [ ] **Step 3: Add deduplication logic**

```swift
private func isDuplicate(_ autoEvent: CircadianEvent) -> Bool {
    events.contains { existing in
        existing.type == autoEvent.type &&
        abs(existing.absoluteHour - autoEvent.absoluteHour) < 0.5
    }
}
```

- [ ] **Step 4: Modify addEvent to skip CloudKit for auto-events**

Change `addEvent()` (currently at line ~739):

```swift
func addEvent(_ event: CircadianEvent) {
    events.append(event)
    events.sort { $0.absoluteHour < $1.absoluteHour }
    #if os(iOS)
    WatchConnectivityManager.shared.sendEvents(events)
    #endif
    // Only sync manual events to CloudKit — auto-events are device-local
    if event.source == .manual {
        cloudSync?.enqueueEventSave(event)
    }
}
```

- [ ] **Step 5: Modify removeEvent to track deleted auto-events**

Change `removeEvent(id:)` (currently at line ~761):

```swift
func removeEvent(id: UUID) {
    // Track deleted auto-events to prevent re-import
    if let event = events.first(where: { $0.id == id }), event.source == .healthKit {
        deletedAutoEventKeys.insert(autoEventKey(event))
    }
    events.removeAll { $0.id == id }
    #if os(iOS)
    WatchConnectivityManager.shared.sendEvents(events)
    #endif
    cloudSync?.enqueueEventDelete(id: id)
}
```

- [ ] **Step 6: Add importHealthKitEvents()**

Add after `refreshHealthProfiles()`:

```swift
/// Import workouts, caffeine, and high HR alerts from HealthKit as auto-events.
func importHealthKitEvents() async {
    #if targetEnvironment(simulator)
    return  // No HealthKit on simulator
    #else
    let hk = HealthKitManager.shared
    guard hk.isAuthorized else { return }

    // Personalized HR threshold: restingHR + 40, fallback 120
    let hrThreshold = (healthProfiles.last?.restingHR).map { $0 + 40 } ?? 120.0

    for profile in healthProfiles {
        let date = profile.date

        let workouts = await hk.fetchWorkouts(for: date)
        let caffeine = await hk.fetchCaffeineIntake(for: date)
        let hrAlerts = await hk.fetchHighHRAlerts(for: date, threshold: hrThreshold)

        var autoEvents: [CircadianEvent] = []

        for w in workouts {
            autoEvents.append(CircadianEvent(
                type: .exercise,
                absoluteHour: absoluteHour(from: w.startDate),
                timestamp: w.startDate,
                durationHours: w.durationHours,
                source: .healthKit
            ))
        }

        for c in caffeine {
            autoEvents.append(CircadianEvent(
                type: .caffeine,
                absoluteHour: absoluteHour(from: c.date),
                timestamp: c.date,
                source: .healthKit
            ))
        }

        for alertDate in hrAlerts {
            autoEvents.append(CircadianEvent(
                type: .highHR,
                absoluteHour: absoluteHour(from: alertDate),
                timestamp: alertDate,
                source: .healthKit
            ))
        }

        for event in autoEvents {
            if !isDuplicate(event) && !isDeletedAutoEvent(event) {
                addEvent(event)
            }
        }
    }
    #endif
}
```

- [ ] **Step 7: Call importHealthKitEvents from refreshHealthProfiles**

At the end of `refreshHealthProfiles()`, after the profiles are sorted (line ~517):

```swift
// Auto-import HealthKit events (workouts, caffeine, HR alerts)
await importHealthKitEvents()
```

- [ ] **Step 8: Build the app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED

---

## Chunk 4: UI Changes + Localization

### Task 4: Filter highHR from manual logging UI

**Files:**
- Modify: `spiral journey project/Views/Panels/EventPanelView.swift:23`
- Modify: `spiral journey project/Views/Tabs/SpiralTab.swift:1834`
- Modify: `spiral journey project/Views/Charts/PRCChartView.swift:63`

- [ ] **Step 1: Filter EventPanelView**

At line 23 of `EventPanelView.swift`, change:
```swift
ForEach(EventType.allCases, id: \.self) { type in
```
to:
```swift
ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
```

- [ ] **Step 2: Filter SpiralTab event grid**

At line 1834 of `SpiralTab.swift`, change:
```swift
ForEach(EventType.allCases, id: \.self) { type in
```
to:
```swift
ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
```

- [ ] **Step 3: Filter PRCChartView**

At line 63 of `PRCChartView.swift`, change:
```swift
ForEach(EventType.allCases, id: \.self) { type in
```
to:
```swift
ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
```

(highHR has no PRC model — it's not a zeitgeber, it's a physiological alert.)

- [ ] **Step 4: Filter Watch app event grid**

At line 31 of `Spiral Watch App Watch App/WatchEventLogView.swift`, change:
```swift
ForEach(EventType.allCases, id: \.self) { type in
```
to:
```swift
ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
```

### Task 5: Show ⌚ icon for auto-events in event list

**Files:**
- Modify: `spiral journey project/Views/Panels/EventPanelView.swift:39-50`

- [ ] **Step 1: Add Watch icon after the event type symbol**

In the `ForEach(events)` block (line 38-66), after the event type icon (line 40-43), add:

```swift
if event.source == .healthKit {
    Image(systemName: "applewatch")
        .font(.caption2)
        .foregroundStyle(SpiralColors.muted)
}
```

So the HStack becomes:
```swift
HStack(spacing: 6) {
    Image(systemName: event.type.sfSymbol)
        .font(.caption)
        .foregroundStyle(Color(hex: event.type.hexColor))
        .frame(width: 14)
    if event.source == .healthKit {
        Image(systemName: "applewatch")
            .font(.caption2)
            .foregroundStyle(SpiralColors.muted)
    }
    Text(NSLocalizedString("event.type.\(event.type.rawValue)", bundle: bundle, comment: ""))
    // ... rest unchanged
}
```

### Task 6: Add PhaseResponse model for highHR (no-op)

**Files:**
- Modify: `SpiralKit/Sources/SpiralKit/Analysis/PhaseResponse.swift`

- [ ] **Step 1: Add highHR to the PhaseResponse.models dictionary**

The `models` dictionary maps `EventType` to `PRCModel`. Since highHR is not a zeitgeber, it should NOT have a PRC entry. But check if any code iterates `EventType.allCases` and looks up `PhaseResponse.models[type]` — if so, it will get `nil` for `.highHR`, which is correct (the existing code already handles nil with `??` or `guard`).

`PhaseResponseTests.swift:50` and `MealStressTests.swift:54` both iterate `EventType.allCases` and assert `PhaseResponse.models[eventType] != nil`. Adding `.highHR` without a PRC entry will break those tests. Fix both to filter:

In `PhaseResponseTests.swift` line 50:
```swift
for eventType in EventType.allCases where eventType.isManuallyLoggable {
```

In `MealStressTests.swift` line 54 (or similar):
```swift
for eventType in EventType.allCases where eventType.isManuallyLoggable {
```

`.highHR` is not a zeitgeber — it has no PRC model. This is correct.

### Task 7: Localization strings

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

- [ ] **Step 1: Add localization keys**

Add to `Localizable.xcstrings` at correct alphabetical positions:

**`event.type.highHR`** (label shown in event list):
en: "High HR" | es: "FC Elevada" | ca: "FC Elevada" | de: "Hohe HF" | fr: "FC Élevée" | zh-Hans: "高心率" | ja: "高心拍" | ar: "معدل نبض مرتفع"

**`event.source.healthKit`** (tooltip or accessibility):
en: "From Apple Watch" | es: "Desde Apple Watch" | ca: "Des d'Apple Watch" | de: "Von Apple Watch" | fr: "Depuis Apple Watch" | zh-Hans: "来自 Apple Watch" | ja: "Apple Watchから" | ar: "من Apple Watch"

### Task 8: Final verification

- [ ] **Step 1: Run SpiralKit tests**

Run: `cd "/Users/xaron/Desktop/spiral journey project/SpiralKit" && swift test`
Expected: ALL PASS

- [ ] **Step 2: Build the full app**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`
Expected: BUILD SUCCEEDED
