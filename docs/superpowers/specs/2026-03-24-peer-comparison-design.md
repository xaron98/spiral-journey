# Peer Sleep Comparison — Fase 12 Design Spec

## Overview

Two iPhones running Spiral Journey can compare their sleep profiles side-by-side via Multipeer Connectivity. Privacy-first: only aggregated metrics are transmitted (no raw sleep records). Data is ephemeral — exists only while connected, deleted on disconnect.

**Goals:**
- Discover nearby peers automatically when both open the comparison screen
- Exchange a ~2KB aggregated payload (no raw records, no health data, no events)
- Display side-by-side comparison cards with bars, values, and overlaid periodograms
- Ephemeral session — data deleted from memory on disconnect

**Non-goals:**
- Cloud-based comparison (no server)
- Persistent history of comparisons
- Raw data sharing (records, phases, events)
- Watch app support

## Architecture

### Component 1: PeerComparisonManager (Service)

**File:** `spiral journey project/Services/PeerComparisonManager.swift`

**Pattern:** `@Observable` class conforming to `MCSessionDelegate`, `MCNearbyServiceBrowserDelegate`, `MCNearbyServiceAdvertiserDelegate`.

**Service type:** `"spiral-compare"` (Bonjour, max 15 chars)

**State machine:**
```
idle → searching → connected → disconnected → idle
```

**Properties:**
```swift
@Observable
final class PeerComparisonManager: NSObject {
    enum State { case idle, searching, connected, disconnected }

    var state: State = .idle
    var peerAlias: String?               // nil until connected
    var peerPayload: ComparisonPayload?  // nil until received, cleared on disconnect

    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var myPeerID: MCPeerID
}
```

**Methods:**
- `startSearching(alias: String, myPayload: ComparisonPayload)` — create session, start browsing + advertising simultaneously
- `stopSearching()` — stop browser + advertiser, disconnect session, clear peer data
- `disconnect()` — end session, set state to `.disconnected`, nil out `peerPayload` and `peerAlias`

**Connection flow:**
1. `startSearching()` → creates `MCSession`, starts `MCNearbyServiceBrowser` + `MCNearbyServiceAdvertiser`
2. Browser finds a peer → auto-invite (no manual approval needed since both are actively searching)
3. Advertiser receives invitation → auto-accept
4. Session connects → exchange `ComparisonPayload` via `session.send()`
5. On receive → decode payload, set `peerPayload` and `peerAlias`, set state to `.connected`
6. On peer disconnect → clear peer data, set state to `.disconnected`

**Alias in discovery info:** Pass the alias as `discoveryInfo: ["alias": alias]` in the advertiser, so the browser can show it before connecting.

**Auto-accept policy:** Both devices are actively in the comparison screen, so auto-accept is safe. No need for manual invitation dialog.

### Component 2: ComparisonPayload (SpiralKit)

**File:** `SpiralKit/Sources/SpiralKit/Models/ComparisonPayload.swift`

```swift
public struct ComparisonPayload: Codable, Sendable {
    public let alias: String
    public let consistencyScore: Int           // 0-100
    public let meanDuration: Double            // hours
    public let sleepRegularityIndex: Double    // 0-100
    public let socialJetlag: Double            // hours
    public let chronotype: String              // "morning" / "intermediate" / "evening"
    public let meanAcrophase: Double           // hour of day (0-24)
    public let meanBedtime: Double             // hour of day
    public let meanWake: Double                // hour of day
    public let periodogramPeaks: [PeakSummary] // from Lomb-Scargle
    public let circadianCoherence: Double      // 0-1
    public let fragmentationScore: Double      // 0-1
    public let recordCount: Int                // days of data
}

public struct PeakSummary: Codable, Sendable {
    public let period: Double       // hours
    public let power: Double        // normalized
    public let label: String?       // "circadian", "weekly", etc.
}
```

**Builder:** Static method `ComparisonPayload.build(from store: ..., analysis: ..., dnaProfile: ...)` that assembles the payload from existing computed data. No new computation needed — all values already exist in `AnalysisResult`, `SleepStats`, `SpiralConsistencyScore`, `SleepDNAProfile`.

### Component 3: PeerComparisonView (UI)

**File:** `spiral journey project/Views/Comparison/PeerComparisonView.swift`

**Access:** Button next to the AI chat button (wherever that is in the UI). Opens as a `.sheet`.

#### State 1: Searching

- Pulsating concentric circles animation (radar effect)
- Text: "Acerca otro iPhone con Spiral Journey" (localized)
- User's alias shown: "Compartiendo como: Xaron"
- "Cancelar" button to dismiss

#### State 2: Connected — Comparison

ScrollView with side-by-side cards:

**Header card:**
- Both aliases with colored dots (blue = you, orange = peer)
- Days of data for each ("14 días" / "32 días")

**Metric cards** (one per metric):
- Label (localized)
- Two horizontal bars (blue/orange) proportional to value
- Numeric values at the ends
- Cards for: Consistency, Duration, Regularity, Social Jetlag, Chronotype, Acrophase, Schedule (bedtime→wake), Coherence, Fragmentation

**Periodogram overlay card:**
- Swift Charts with two `LineMark` series (blue = you, orange = peer)
- Shared X-axis (period, log scale)
- Only if both users have periodogram data (≥14 days each)

#### State 3: Disconnected

- "Conexión terminada" message
- "Buscar de nuevo" button → returns to searching
- All peer data cleared

### Component 4: Settings — Alias Configuration

**File:** Modify `spiral journey project/Views/Tabs/SettingsTab.swift`

Add a text field in Settings for the comparison alias:
```swift
TextField("Alias", text: $store.comparisonAlias)
```

**Storage:** `comparisonAlias: String` in `SpiralStore`, persisted in UserDefaults. Default: device name truncated to 20 chars.

**Also add:** Button "Comparar sueño" that opens `PeerComparisonView` as a sheet.

## Data Flow

```
User opens PeerComparisonView
  ↓
PeerComparisonManager.startSearching(alias, myPayload)
  ↓
MCNearbyServiceBrowser discovers peer
  ↓
Auto-invite → auto-accept → MCSession connected
  ↓
Both send ComparisonPayload via session.send()
  ↓
PeerComparisonView shows side-by-side comparison
  ↓
User dismisses → PeerComparisonManager.disconnect()
  ↓
peerPayload = nil, peerAlias = nil (ephemeral)
```

## Edge Cases

- **Only one device searching:** Nothing happens — browser finds no peers. Shows searching animation indefinitely until cancel.
- **Different app versions:** `ComparisonPayload` is Codable with fixed fields. If a newer version adds fields, `decodeIfPresent` ensures backward compatibility.
- **Connection drops mid-session:** `MCSessionDelegate.session(_:peer:didChange:)` fires `.notConnected` → clear peer data, show disconnected state.
- **User has < 7 days of data:** Still works — some metrics will be 0 or unavailable. Show "—" for metrics that need more data.
- **Periodogram not available for one user:** Hide the overlay card, show only available metric cards.
- **Both devices are the same iCloud account:** Works fine — Multipeer doesn't care about iCloud identity.
- **Bluetooth off:** Multipeer works over WiFi too. If neither is available, browser finds nothing.

## Privacy Guarantees

1. **No raw data transmitted** — only pre-computed aggregates
2. **Local only** — Multipeer Connectivity, no internet, no server
3. **Encrypted** — MCSession uses encryption by default (`.required`)
4. **Ephemeral** — peer data cleared from memory on disconnect
5. **Explicit consent** — user must open the comparison screen (opt-in per session)
6. **No identifiable health data** — aggregated metrics (mean duration, consistency score) are not HealthKit data

## Files

| Action | File | Change |
|--------|------|--------|
| Create | `SpiralKit/Sources/SpiralKit/Models/ComparisonPayload.swift` | Payload model + PeakSummary + builder |
| Create | `spiral journey project/Services/PeerComparisonManager.swift` | MC session, browser, advertiser, state machine |
| Create | `spiral journey project/Views/Comparison/PeerComparisonView.swift` | 3-state UI (searching, connected, disconnected) |
| Modify | `spiral journey project/Services/SpiralStore.swift` | Add `comparisonAlias` property |
| Modify | `spiral journey project/Views/Tabs/SettingsTab.swift` | Add alias field |
| Modify | (view with AI chat button) | Add "Comparar" button next to AI chat |
| Modify | `spiral journey project/Localizable.xcstrings` | Comparison UI strings (9 languages) |

## Testing Strategy

**Unit tests (SpiralKit):**
- ComparisonPayload.build() produces correct values from mock data
- ComparisonPayload encodes/decodes correctly
- PeakSummary roundtrips through Codable

**Integration (requires 2 devices):**
- Both open comparison → discover each other
- Payloads exchanged and displayed correctly
- Disconnect → peer data cleared
- Re-search after disconnect works
- One closes screen → other sees disconnected state
- Different data amounts (7 days vs 60 days) display gracefully

## Localization

New keys (8 languages):
- `comparison.title` — "Comparar Sueño" / "Compare Sleep"
- `comparison.searching` — "Acerca otro iPhone con Spiral Journey"
- `comparison.sharingAs` — "Compartiendo como: %@"
- `comparison.disconnected` — "Conexión terminada"
- `comparison.searchAgain` — "Buscar de nuevo"
- `comparison.days` — "%d días de datos"
- `comparison.alias` — "Alias para comparación"
- `comparison.you` — "Tú"
- Metric labels reuse existing localization keys (consistency, duration, etc.)
