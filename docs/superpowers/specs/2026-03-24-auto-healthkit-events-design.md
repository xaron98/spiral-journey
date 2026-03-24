# Auto HealthKit Events + HR Alert — Fase C Design Spec

## Overview

Auto-populate CircadianEvents on the spiral from HealthKit data: workouts, caffeine intake, and high heart rate alerts. Events appear identical to manually logged ones — same colors, same rendering. No new visual layers or second tracks.

**Goals:**
- Workouts from Apple Watch appear as `.exercise` events automatically
- Caffeine from Health-compatible apps appears as `.caffeine` events automatically
- Elevated heart rate (non-workout) appears as a new `.highHR` event type
- Deduplicate against manually logged events (±30 min same type)
- Graceful degradation: no Watch → no auto-events, app works as before

**Non-goals (deferred):**
- Second parallel activity track on spiral (see memory: project_future_second_track)
- Continuous HR signal visualization (zigzag/waveform)
- Auto-events for meal, stress, alcohol (no reliable HealthKit source)
- Autocorrelation heatmap (already exists in AnalysisTab)

## Architecture

### Component 1: CircadianEvent Model Changes (SpiralKit)

**File:** `SpiralKit/Sources/SpiralKit/Models/CircadianEvent.swift`

#### Add source field

```swift
public enum EventSource: String, Codable, Sendable {
    case manual      // user-logged
    case healthKit   // auto-imported from HealthKit
}
```

Add to `CircadianEvent`:
```swift
public var source: EventSource
```

**Updated init signature** (backward compatible — `source` defaults to `.manual`):
```swift
public init(
    id: UUID = UUID(),
    type: EventType,
    absoluteHour: Double,
    timestamp: Date,
    note: String? = nil,
    durationHours: Double? = nil,
    source: EventSource = .manual    // ← new, defaulted
)
```

**Codable compatibility:** Add custom `init(from:)` that uses `decodeIfPresent(EventSource.self, forKey: .source) ?? .manual` so existing persisted events without the `source` key decode correctly. No changes needed to `Stored` struct in SpiralStore — it uses `[CircadianEvent]` which handles itself.

#### Add highHR event type

Add to `EventType`:
```swift
case highHR  // "High Heart Rate" (#ff6b6b) — heart.fill
```

Properties:
- `label`: "High Heart Rate"
- `hexColor`: "#ff6b6b"
- `sfSymbol`: "heart.fill"
- `hasDuration`: false (instant event — marks the moment HR exceeded threshold)

**CaseIterable guard:** `EventType` conforms to `CaseIterable`. The event logging UI (`EventPanelView.swift`) iterates `EventType.allCases` to render the manual logging grid. `.highHR` must NOT appear as a manually-loggable option. Add a computed property:

```swift
public var isManuallyLoggable: Bool {
    self != .highHR
}
```

`EventPanelView` filters: `EventType.allCases.filter(\.isManuallyLoggable)` instead of `EventType.allCases`.

### Component 2: HealthKit Fetch Methods

**File:** `spiral journey project/Services/HealthKitManager.swift`

#### New HealthKit types to add to `fitnessReadTypes`

```swift
HKQuantityType(.dietaryCaffeine),
HKCategoryType(.highHeartRateEvent),
```

Both must be added to the `fitnessReadTypes` set so they are included in the authorization request. The `NSHealthShareUsageDescription` in Info.plist already mentions "heart rate" and covers these additions.

#### fetchWorkouts(for date) → [WorkoutEvent]

```swift
struct WorkoutEvent {
    let startDate: Date
    let endDate: Date
    let durationHours: Double
    let workoutType: HKWorkoutActivityType
}
```

Query `HKWorkoutType.workoutType()` for the given day using `HKSampleQuery` with date predicate. Return start, end, duration, and activity type.

#### fetchCaffeineIntake(for date) → [CaffeineEvent]

```swift
struct CaffeineEvent {
    let date: Date
    let milligrams: Double
}
```

Query `HKQuantityType(.dietaryCaffeine)` samples for the given day. Return each sample's timestamp and quantity in mg.

#### fetchHighHRAlerts(for date) → [Date]

**Two-tier approach:**

1. **Primary:** Query `HKCategoryType(.highHeartRateEvent)` — Apple Watch generates these based on the user's configured threshold. If samples exist, return their timestamps directly (no custom threshold logic needed).

2. **Fallback (if no system alerts exist):** Query `HKQuantityType(.heartRate)` samples, filter where HR > threshold AND not during a workout. Cluster consecutive high-HR samples (within 5 min) into a single alert at the peak timestamp.

**Threshold for fallback:**
```swift
func resolveHRThreshold() -> Double {
    // Most recent resting HR + 40 bpm (healthProfiles sorted by day ascending)
    if let restingHR = healthProfiles.last?.restingHR {
        return restingHR + 40
    }
    return 120  // conservative default
}
```

### Component 3: Auto-Event Generation

**File:** `spiral journey project/Services/SpiralStore.swift`

#### absoluteHour computation

The existing codebase computes `absoluteHour` as hours from `startDate`. For auto-events from HealthKit dates, use:

```swift
private func absoluteHour(from date: Date) -> Double {
    date.timeIntervalSince(startDate) / 3600.0
}
```

This matches how manual events compute their `absoluteHour` from the cursor position (which is also hours from startDate).

#### New method: importHealthKitEvents()

Called from `refreshHealthProfiles()` (which runs in the 4AM background task and on foreground). Processes all days that have DayHealthProfile data.

```swift
func importHealthKitEvents() async {
    let hk = HealthKitManager.shared

    for profile in healthProfiles {
        let date = profile.date

        // 1. Fetch HealthKit data
        let workouts = await hk.fetchWorkouts(for: date)
        let caffeine = await hk.fetchCaffeineIntake(for: date)
        let hrAlerts = await hk.fetchHighHRAlerts(for: date)

        // 2. Convert to CircadianEvents
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

        // 3. Deduplicate and add
        for event in autoEvents {
            if !isDuplicate(event) && !isDeletedAutoEvent(event) {
                addEvent(event)
            }
        }
    }
}
```

#### Deduplication logic

For each auto-event, check existing `events` array:
- Same `EventType`
- `absoluteHour` within ±0.5 hours (30 min) of existing event
- If match found → skip (manual event takes priority)

```swift
private func isDuplicate(_ autoEvent: CircadianEvent) -> Bool {
    events.contains { existing in
        existing.type == autoEvent.type &&
        abs(existing.absoluteHour - autoEvent.absoluteHour) < 0.5
    }
}
```

#### Deleted auto-event tracking

When the user deletes an auto-event, store its `timestamp` + `type` as a composite key to prevent re-import.

```swift
/// Persisted in UserDefaults (App Group) as JSON-encoded array.
private(set) var deletedAutoEventKeys: Set<String> = []

/// Composite key: "type|timestamp_epoch"
private func autoEventKey(_ event: CircadianEvent) -> String {
    "\(event.type.rawValue)|\(Int(event.timestamp.timeIntervalSince1970))"
}

private func isDeletedAutoEvent(_ event: CircadianEvent) -> Bool {
    deletedAutoEventKeys.contains(autoEventKey(event))
}
```

Modify `removeEvent(id:)`: if the removed event has `source == .healthKit`, add its key to `deletedAutoEventKeys`.

**Persistence:** `deletedAutoEventKeys` stored in App Group UserDefaults under key `"spiral-journey-deleted-auto-events"`. Not synced via CloudKit (device-local preference).

#### CloudKit sync for auto-events

Auto-events (source: `.healthKit`) are **NOT synced to CloudKit**. Modify `addEvent()` to skip `cloudSync?.enqueueEventSave(event)` when `event.source == .healthKit`. Each device imports its own HealthKit data independently — no cross-device duplication risk.

Auto-events ARE sent to Apple Watch via `WatchConnectivityManager` (so the Watch app can display them).

### Component 4: UI indicator for auto-events

**File:** `spiral journey project/Views/Panels/EventPanelView.swift`

No visual difference on the spiral (same rendering). But in the event list within `EventPanelView`, show a small Apple Watch SF Symbol (`applewatch`) next to auto-imported events so the user knows where they came from.

Users can delete auto-events (they won't re-import thanks to the deleted keys tracking).

## Data Flow

```
Background task (4AM) or foreground refresh
  ↓
HealthKitManager.fetchWorkouts/fetchCaffeine/fetchHighHRAlerts
  ↓
SpiralStore.importHealthKitEvents()
  ↓
Deduplication check (existing events + deleted keys)
  ↓
store.addEvent() for non-duplicates (source: .healthKit, no CloudKit sync)
  ↓
Normal rendering pipeline (drawEventMarkers + drawEventArcs)
```

## Edge Cases

- **No Watch:** fetchWorkouts/fetchCaffeine/fetchHighHRAlerts return empty arrays. No auto-events generated.
- **User denies HealthKit access:** Same as no Watch — empty arrays.
- **Workout overlaps with manual exercise:** Deduplication catches it (±30 min same type).
- **Multiple caffeine entries same hour:** Each gets dedup-checked independently. If user logged caffeine at 14:00 and HK has samples at 13:45 and 14:15, the 13:45 one is deduped (within 30min of manual), the 14:15 one is added.
- **HR high during workout:** Filtered out — only non-workout HR elevations generate alerts.
- **User deletes auto-event:** Key added to `deletedAutoEventKeys`, won't re-import on next refresh.
- **Existing events without `source` field:** Decode as `.manual` via `decodeIfPresent` fallback.
- **Both devices import same workout via HealthKit:** No issue — CloudKit sync is disabled for auto-events. Each device has its own local copy.

## Files Modified

| Action | File | Change |
|--------|------|--------|
| Modify | `SpiralKit/.../CircadianEvent.swift` | Add `EventSource` enum, `source` field, custom Codable, `highHR` event type, `isManuallyLoggable` |
| Modify | `spiral journey project/Services/HealthKitManager.swift` | Add `dietaryCaffeine` + `highHeartRateEvent` to auth, add fetchWorkouts, fetchCaffeineIntake, fetchHighHRAlerts |
| Modify | `spiral journey project/Services/SpiralStore.swift` | Add importHealthKitEvents(), deduplication, deletedAutoEventKeys, absoluteHour(from:), skip CloudKit for auto-events |
| Modify | `spiral journey project/Views/Panels/EventPanelView.swift` | Filter `.isManuallyLoggable` in event grid, show ⌚ icon for .healthKit events |
| Modify | `spiral journey project/Localizable.xcstrings` | Add highHR label, auto-event indicator strings |

## Testing Strategy

**SpiralKit unit tests:**
- CircadianEvent with `source: .healthKit` encodes/decodes correctly
- CircadianEvent without `source` key in JSON decodes as `.manual` (backward compat)
- EventType.highHR has correct label, hexColor, sfSymbol, hasDuration=false
- EventType.highHR.isManuallyLoggable == false
- All other EventTypes have isManuallyLoggable == true

**Integration (manual, on device):**
- Do a workout → verify it appears on spiral after refresh
- Log manual exercise → do workout at similar time → verify no duplicate
- Check HR alert appears when elevated HR was recorded
- Delete an auto-event → refresh → verify it doesn't reappear
- Verify EventPanelView does NOT show highHR as a logging option
- Verify ⌚ icon appears next to auto-events in event list
- Verify app works normally without Watch data (no crashes, no phantom events)

## Localization

New keys needed (8 languages: ar, ca, de, en, es, fr, ja, zh-Hans):
- `event.highHR.label` — "High Heart Rate" / "FC Elevada" / ...
- `event.source.healthKit` — "From Apple Watch" / "Desde Apple Watch" / ...
