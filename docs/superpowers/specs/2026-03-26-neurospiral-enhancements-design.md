# NeuroSpiral Enhancements — Design Spec

**Date:** 2026-03-26
**Scope:** Hub refactor + night history + animated trajectory + CSV export with Python loader + Watch minicard
**Approach:** B — Dashboard hub with hero metrics + detail views via NavigationLink

---

## 1. Hub Refactor (NeuroSpiralView)

### Current state
`NeuroSpiralView.swift` (649 lines) is a single ScrollView with all cards inline: torus projection, vertex residence, oscillators, transitions, dominant state, plus the full info sheet.

### Target state
Refactor into a compact dashboard hub. The heavy analysis logic (`loadAndAnalyze`, `buildSamplesFromRecords`) stays in NeuroSpiralView. Sub-views receive computed data, not raw records.

### Layout (top to bottom)

1. **Header card** — icon + title + subtitle (unchanged)
2. **Hero metrics row** — 3 equal-width columns:
   - Estabilidad: `XX%` (green >60%, orange 40-60%, red <40%)
   - Dominante: `V₀₅` with sign code `[+−+−]`
   - Winding: `ω₁/ω₂` ratio (or `—` if undefined)
3. **Mini torus scatter** — Canvas, height 200pt (down from 250). Same projection code, no legend (legend in detail). Tappable → pushes `NeuroSpiralTorusDetailView`.
4. **Action buttons row** — 3 buttons in HStack:
   - "Historial" (clock.arrow.circlepath) → pushes `NeuroSpiralHistoryView`
   - "Trayectoria" (point.3.connected.trianglepath.dotted) → pushes `NeuroSpiralTrajectoryView`
   - "Exportar" (square.and.arrow.up) → pushes `NeuroSpiralExportView`
5. **Dominant state card** — compact version: 4 dimension rows only, no residence % text
6. **Toolbar** — close (leading), info (trailing, opens existing info sheet)

### Data flow

```
NeuroSpiralView
  ├─ @State analysis: SleepTrajectoryAnalysis?
  ├─ @State perNightAnalyses: [NightAnalysis]   // NEW
  ├─ @State samples: [WearableSleepSample]       // NEW (retained for export)
  │
  ├─ .task { loadAndAnalyze() }
  │    ├─ builds samples from store.records + store.hrvData
  │    ├─ runs mapper.analyzeNight(allSamples) → analysis
  │    ├─ runs analyzePerNight(records, hrvData) → perNightAnalyses
  │    └─ persists baseline to App Group UserDefaults
  │
  ├─ NavigationLink → TorusDetailView(analysis)
  ├─ NavigationLink → HistoryView(perNightAnalyses)
  ├─ NavigationLink → TrajectoryView(analysis)
  └─ NavigationLink → ExportView(samples, analysis)
```

### New types

```swift
/// Per-night summary for history view
struct NightAnalysis: Identifiable {
    let id: UUID
    let date: Date
    let stability: Double          // 0-1
    let dominantVertex: Int        // 0-15
    let omega1: Double
    let omega2: Double
    let windingRatio: Double?
    let transitionCount: Int
    let sampleCount: Int
}
```

### Baseline persistence

```swift
// On every analysis completion:
let encoded = try JSONEncoder().encode(mapper.baseline)
UserDefaults(suiteName: "group.xaron.spiral-journey-project")?.set(encoded, forKey: "neurospiral-baseline")

// On load:
if let data = UserDefaults(suiteName: "group.xaron.spiral-journey-project")?.data(forKey: "neurospiral-baseline"),
   let saved = try? JSONDecoder().decode(WearableTo4DMapper.PersonalBaseline.self, from: data) {
    mapper.baseline = saved
}
```

`PersonalBaseline` is already `Codable` + `Sendable` in the package.

### Files changed/created

| Action | File |
|--------|------|
| Refactor | `Views/DNA/NeuroSpiralView.swift` — hub dashboard |
| Create | `Views/DNA/NeuroSpiralTorusDetailView.swift` — full torus with legend + vertex residence |
| Create | `Views/DNA/NeuroSpiralHistoryView.swift` — per-night sparklines |
| Create | `Views/DNA/NeuroSpiralTrajectoryView.swift` — animated trajectory |
| Create | `Views/DNA/NeuroSpiralExportView.swift` — CSV generation + share |

---

## 2. History View

### What it shows
Last 7-14 nights of NeuroSpiral analysis, each as a row or mini-card.

### Layout

1. **Stability sparkline** — line chart across nights (Canvas, 7-14 points). Green/orange threshold at 60%.
2. **Winding ratio sparkline** — second line below, teal color.
3. **Night list** — each row:
   - Date (left)
   - Stability % gauge (center)
   - Dominant vertex badge `V₀₅` (right)
   - Transition count as subtitle
4. Tap a night → could expand inline or navigate further (inline expand for v1).

### Data source
`perNightAnalyses: [NightAnalysis]` computed in the hub's `.task`. Each night runs `mapper.analyzeNight()` independently on that night's samples.

### Implementation detail
The `analyzePerNight` function iterates `store.records.suffix(14)`, builds samples per-record using the same `buildSamplesFromRecords` logic but filtering by single record, and returns `[NightAnalysis]`.

---

## 3. Animated Trajectory View

### What it shows
The torus scatter plot, but points appear progressively over time — like watching the sleep journey unfold on the donut surface.

### Mechanics

- Same Canvas-based torus projection as the hub
- `@State private var visibleCount: Int = 0` — how many trajectory points to draw
- `TimelineView(.periodic(from: .now, by: 1.0 / 30.0))` drives the animation at 30fps
- Each frame: `visibleCount = min(visibleCount + pointsPerFrame, trajectory.count)`
- Lines connect consecutive points with decreasing opacity (trail effect)
- **Playback controls**: play/pause button + speed slider (1x, 2x, 5x, 10x)
- Reset button to restart from 0

### Visual details

- Current point: larger dot (radius 4) with glow
- Trail: last 20 points connected with lines, opacity fading from 1.0 to 0.1
- Historical points: small dots (radius 2), purple at 30% opacity
- Vertex markers: orange circles (same as hub)
- Dominant vertex: green (same as hub)

### Why TimelineView not Timer
`TimelineView` is the SwiftUI-native approach for frame-driven animation. No need for CADisplayLink here since we're not transforming a RealityKit entity — this is purely 2D Canvas drawing.

---

## 4. CSV Export + Python Loader

### iOS side: NeuroSpiralExportView

**CSV format** (one row per epoch):

```csv
timestamp_iso,hrv_ms,heart_rate_bpm,motion_intensity,sleep_phase,theta,phi,vertex_idx,vertex_code,omega1,omega2
2026-03-25T23:30:00Z,52.3,58.2,0.01,deep,-1.234,0.567,5,+--+,0.342,0.278
```

Columns:
- `timestamp_iso` — ISO 8601
- `hrv_ms` — HRV in milliseconds
- `heart_rate_bpm` — HR in BPM
- `motion_intensity` — 0.0-1.0
- `sleep_phase` — deep/rem/light/awake (SpiralKit phase name)
- `theta`, `phi` — torus angles from CliffordTorus.angles()
- `vertex_idx` — 0-15
- `vertex_code` — sign pattern like `+--+`
- `omega1`, `omega2` — angular velocities (computed per-epoch as rolling window)

**Generation flow:**
1. Uses the retained `samples: [WearableSleepSample]` + `analysis: SleepTrajectoryAnalysis`
2. Maps each sample → 4D point → torus angles → vertex
3. Computes per-epoch ω from consecutive angle differences
4. Writes to temporary file in App Group container
5. Presents `ShareLink` for AirDrop / Files / email

**View layout:**
- Summary: N epochs, date range, nights covered
- Preview: first 5 rows in monospaced text
- "Exportar CSV" button → ShareLink
- Info text: "Compatible con el pipeline NeuroSpiral Python"

### Python side: src/data/watch_loader.py

```python
@dataclass
class WatchRecord:
    """Container for Apple Watch sleep export."""
    subject_id: str
    epochs: np.ndarray          # (N, 4) — [hrv, hr, motion, circadian]
    labels: np.ndarray          # (N,) — integer stage labels
    torus_coords: np.ndarray    # (N, 4) — Clifford torus points
    torus_angles: np.ndarray    # (N, 2) — (theta, phi)
    vertex_assignments: np.ndarray  # (N,) — vertex indices 0-15
    timestamps: list[datetime]

def load_watch_csv(csv_path: Path) -> WatchRecord:
    """Load CSV exported from Spiral Journey iOS app."""
    ...

WATCH_LABEL_MAPPING = {
    "deep": "N3",
    "rem": "REM",
    "light": "N2",
    "awake": "W",
}
```

**Integration with publish_validate.py:**
- New CLI flag: `--input-type watch --watch-csv path/to/export.csv`
- When `input_type == "watch"`: skip EDF download/ICA/Takens, load pre-computed torus coords directly
- Still runs: vertex residence, ω₁/ω₂, transition analysis, Cramér's V, MI
- Cannot run: spectral features (no raw EEG) — skip spectral-only metrics, log warning
- Can run: geometric features vs. sleep stage correlation — the core comparison

---

## 5. Watch Minicard

### Architecture
The Watch does NOT run SpiralGeometry. The iPhone computes the analysis and writes a summary to App Group UserDefaults. The Watch reads it.

### Data written by iPhone

```swift
// Key: "neurospiral-last-night"
struct NeuroSpiralWatchData: Codable {
    let date: Date
    let stability: Double          // 0-1
    let dominantVertexIdx: Int     // 0-15
    let dominantVertexCode: String // "+--+"
    let windingRatio: Double?
    let transitionCount: Int
}
```

Written in `NeuroSpiralView.loadAndAnalyze()` after analysis completes, using `UserDefaults(suiteName: "group.xaron.spiral-journey-project")`.

### Watch view: WatchNeuroSpiralCard.swift

Simple card added as tab 4 (after WatchEventLogView):

```
┌─────────────────────┐
│      ANOCHE          │  ← caption, muted
│                      │
│       78%            │  ← large, green/orange/red
│    estabilidad       │  ← caption
│                      │
│    V₀₅ [+−+−]       │  ← purple, monospaced
│  estado dominante    │  ← caption
│                      │
│    ω₁/ω₂ = 1.23     │  ← teal, small
│    12 transiciones   │  ← muted, small
└─────────────────────┘
```

Colors: `WatchColors` palette (no asset catalog on watchOS, per CLAUDE.md rules).

### Files changed/created

| Action | File |
|--------|------|
| Create | `Spiral Watch App Watch App/WatchNeuroSpiralCard.swift` |
| Modify | `Spiral Watch App Watch App/ContentView.swift` — add tab 4 |
| Modify | `spiral journey project/Views/DNA/NeuroSpiralView.swift` — write watch data after analysis |

---

## 6. Localization

All new user-facing strings via `NSLocalizedString(_:bundle:comment:)` with keys added to `Localizable.xcstrings` for 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans).

New key prefixes:
- `neurospiral.hub.*` — hero metrics labels
- `neurospiral.history.*` — history view
- `neurospiral.trajectory.*` — animation controls
- `neurospiral.export.*` — export view
- `neurospiral.watch.*` — Watch card (in Watch's own strings if separate, or App Group)

---

## 7. What is NOT in scope

- 3D torus rendering (RealityKit) — future enhancement
- Watch-side SpiralGeometry computation — iPhone only
- TCN model integration — paper #2
- HMC/CAP loaders — after 75-subject results
- Paper figures script — after 75-subject results
- Real-time Watch streaming — the export is batch (last 7-14 nights), not live

---

## 8. Dependencies

- `SpiralGeometry` package (already integrated)
- `SpiralKit` (SleepRecord, NightlyHRV, SleepPhase)
- App Group `group.xaron.spiral-journey-project` (already configured)
- Watch Connectivity (already configured, but Watch card reads UserDefaults directly, not WCSession)
