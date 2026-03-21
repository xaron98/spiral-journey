# DNA Insights Redesign — Story Flow with Progressive Disclosure

## Overview

Redesign the DNAInsightsView from a flat list of 6 identical cards into a narrative "Story Flow" layout with visual hierarchy, human language, and progressive disclosure (simple by default, expandable to technical detail).

**Goals:**
- Fix flat visual hierarchy (all sections same weight → graduated sizing)
- Replace raw numbers (PLV, HB) with human language + expandable detail
- Add mini-visualizations (sparklines, heatmaps, strength bars)
- Surface the sleep prediction prominently (currently buried)
- Add temporal context (trends vs previous week)
- Add actionable insights via deterministic rules + optional Foundation Models (iOS 26)
- Give the 3D helix a structural role (narrative divider, not decoration)

**Non-goals (Phase 2):**
- Intra-night codon analysis (k-mers of sleep stage transitions)
- Foundation Models integration (deterministic rules only in Phase 1)
- Interpersonal comparison features

## Architecture

### Layout: Story Flow (top-to-bottom narrative)

```
┌─────────────────────────────┐
│  1. HERO CARD (large)       │  Estado + predicción + tendencia
├─────────────────────────────┤
│  2. HÉLICE 3D (protagonist) │  Divisor narrativo + tier overlay
├─────────────────────────────┤
│  3. SALUD (medium)          │  Alertas con gradiente
├─────────────────────────────┤
│  4. PATRONES (medium)       │  Motifs humanizados + heatmap
├─────────────────────────────┤
│  5. CONEXIONES (compact)    │  Base pairs como causa-efecto
├─────────────────────────────┤
│  6. SIMILITUD (compact)     │  Alignment + sparkline
├─────────────────────────────┤
│  7. FOOTER (minimal)        │  Disclaimer + tier motivation
└─────────────────────────────┘
```

Visual hierarchy is achieved through graduated card sizing (large → medium → compact → minimal) and typography scale.

### Progressive Disclosure Pattern

Each section has two states:
- **Collapsed (default):** Human-readable summary, mini-visualization, actionable insight
- **Expanded (tap):** Technical details, raw numbers, full data for biohackers

The interaction pattern (inline expand vs push navigation) is chosen per-section based on content volume.

### User Profiles Served

- **Casual user:** Reads the collapsed views, gets value from human language and suggestions
- **Biohacker:** Taps to expand, sees PLV values, DTW scores, coherence percentages

## Section Specifications

### 1. Hero Card (DNAHeroCard)

**Replaces:** `DNAStateSection` + prediction from `DNAAlignmentSection`

**Collapsed state:**
- Circadian state word — large, bold, colored (green/amber/red): "Sincronizado" / "En transición" / "Desalineado"
- Tonight's prediction — "Acuéstate a las 23:30 → Despierta a las 7:15" with confidence as a subtle bar (not a percentage)
- Trend indicator — arrow + short text: "↑ mejorando vs semana pasada" / "→ estable" / "↓ empeorando"

**Expanded state (tap):**
- Coherence percentage
- Homeostasis Balance (HB) value
- HAS score (if available)
- Prediction confidence as number
- Based-on weeks: show count + date ranges of the historical weeks used for prediction (from `prediction.basedOnWeekIndices`, converted to date ranges via nucleotide day indices)

**Trend calculation:** Compare current `circadianCoherence` against mean coherence from the previous `SDSleepDNASnapshot`. If no previous snapshot exists, omit trend.

**Data sources:**
- `profile.healthMarkers.circadianCoherence` → state label + color
- `profile.prediction` → bedtime/wake/confidence
- Previous `SDSleepDNASnapshot` → trend delta

**Visual:** Largest card. Full width, generous padding, large typography. Liquid glass background.

**Code changes:**
- New file: `DNAHeroCard.swift` (replaces `DNAStateSection.swift`)
- `DNAAlignmentSection` loses its prediction display
- New: `TrendCalculator` helper or inline computation using `modelContext` to fetch previous snapshot

### 2. Hélice 3D (HelixRealityView — modified)

**Replaces:** Current `HelixRealityView` placement + `DNATierSection`

**Changes from current:**
- Remove `clipShape(RoundedRectangle)` and dedicated dark background — helix floats on page background
- Add bottom overlay: tier badge + weeks analyzed ("8 semanas · Nivel completo 🟢")
- Week tap action: in addition to showing the floating week info card, scroll to and briefly highlight the Patterns section if the tapped week belongs to a motif (via callback/binding)
- Adaptive height: if `profile.helixGeometry.count < 3`, keep the existing placeholder message (icon + "needs more data" text) already in `HelixRealityView` lines 34-48. Do not use `MiniHelixView` here — it is a decorative 2D Canvas animation with no profile data, not suitable as a data-driven fallback.

**What stays the same:** All gesture handling, auto-rotation, LOD, dirty-tracking, `HelixInteractionManager`.

**Data sources:**
- `profile.tier` + `profile.dataWeeks` → overlay text
- `profile.motifs` → scroll-to target on week tap

**Code changes:**
- Modify `HelixRealityView.swift`: remove clipShape, adjust background, add tier overlay
- Delete `DNATierSection.swift` (absorbed here)
- Add optional `onWeekTapped: ((Int) -> Void)?` callback for scroll-to coordination

### 3. Salud Circadiana (DNAHealthSection — rewritten)

**Replaces:** Current `DNAHealthSection`

**Collapsed state — three variants:**
- No alerts: "✓ Ritmo estable" (green) — single line
- Mild alerts: "⚠ 1 señal a observar" (amber) — single line
- Urgent alerts: "⛔ 2 alertas activas" (red) — auto-expands

**Expanded state (tap, or auto for urgent):**
- Individual alerts with severity icon + localized message (as current)
- **Persistence context** per alert: "Fragmentación alta (3ª semana)" vs "Drift — nuevo esta semana". Requires comparing with previous snapshot alerts.
- **Proximity indicators** when no alert: "Fragmentación: normal (cerca del límite)". Show when a marker is within 20% of its trigger threshold.
- **Actionable insight** per alert type — deterministic rule mapping. Only the 4 alert types currently generated by `HealthMarkerDetector.analyze()` are mapped:
  - `circadianAnarchy` → "Intenta mantener horarios regulares el fin de semana"
  - `highFragmentation` → "Evita pantallas 1h antes de dormir"
  - `severeDrift` → "Tu horario de sueño se está desplazando — intenta fijar la hora de despertar"
  - `highDesynchrony` → "Tu reloj interno y tus horarios no están alineados"
  - Note: `remDriftAbnormal` and `novelPattern` exist in the `AlertType` enum but are never generated by the current detector. No insight rules are needed for them now. If the detector is extended in the future, insight rules can be added then.

**Data sources:**
- `profile.healthMarkers` → alerts, all marker values for proximity
- Previous `SDSleepDNASnapshot` → persistence tracking
- `HealthMarkerDetector` thresholds → proximity calculation

**Code changes:**
- Rewrite `DNAHealthSection.swift` with collapsed/expanded state
- New: `HealthInsightRules.swift` — deterministic mapping of alert type → actionable text (localized)
- Proximity logic: the thresholds in `HealthMarkerDetector` are inline literals (0.2, 0.6, 15, 0.3), not public constants. **Minor SpiralKit change required:** extract these as `public static let` constants on `HealthMarkerDetector` so the view layer can reference them for proximity calculations without duplicating magic numbers.

### 4. Patrones (DNAMotifSection — rewritten)

**Replaces:** Current `DNAMotifSection`

**Collapsed state:**
- Natural language description of dominant motif: "Tu patrón más frecuente: noches tardías (4 de las últimas 8 semanas)"
- Recent mutation with context: "Esta semana dormiste mejor de lo esperado para tu patrón (+12%)" — colored by mutation type (silent=green, missense=amber, nonsense=red)
- Mini heatmap: one row of colored blocks, one per recent week, color = motif assignment. Simple Canvas drawing.

**Expanded state (tap):**
- All discovered motifs with instance count, average quality
- Full mutation history
- Week-by-motif breakdown

**Learning state (<8 weeks):**
- Progress bar (as current) + what unlocks: "5/8 semanas · En 3 semanas más descubriremos tus patrones recurrentes"

**Data sources:**
- `profile.motifs` → dominant motif, all motifs
- `profile.mutations` → recent mutation, history. Each `SleepMutation` has a `motifID: UUID` field that links to the parent motif for context phrases ("better/worse than expected for your pattern")
- `profile.dataWeeks` → learning progress

**Code changes:**
- Rewrite `DNAMotifSection.swift` with collapsed/expanded
- New: mini heatmap Canvas component (`MotifHeatmapBar`)
- Localized motif descriptions (extend existing `localizedMotifName` to full sentences)

### 5. Conexiones (DNABasePairsSection — rewritten)

**Replaces:** Current `DNABasePairsSection`

**Collapsed state:**
- Top 3 connections as natural language cause-effect phrases:
  - "El café influye fuertemente en tu hora de dormir"
  - "El ejercicio mejora moderadamente tu sueño profundo"
  - "El estrés fragmenta tu descanso"
- Strength indicator: visual dots (●●●○○) instead of PLV number. Three levels: strong (PLV > 0.7), moderate (0.4-0.7), weak (< 0.4)
- Actionable insight from `ExpressionRule` when available: "Los días sin café te duermes ~40 min antes"

**Expanded state (tap):**
- All detected base pairs with PLV values, phase difference
- Expression rules with threshold values
- Feature indices for the technically curious

**Hidden in tier basic** — no change to this logic.

**Data sources:**
- `profile.basePairs` → connections, PLV values
- `profile.expressionRules` → actionable insights
- Feature index → localized name mapping (existing `contextFeatureKeys` / `sleepFeatureKeys`)

**Code changes:**
- Rewrite `DNABasePairsSection.swift`
- New: `BasePairDescriptor.swift` — combines `BasePairSynchrony` + `ExpressionRule` → localized cause-effect phrase
- New: `StrengthDotsView` — reusable 3-5 dot indicator component
- Note: `BasePairSynchrony` lacks `Identifiable` conformance. Use `enumerated()` with `id: \.offset` in ForEach loops (matching current pattern in `DNABasePairsSection`)

### 6. Similitud (DNAAlignmentSection — rewritten)

**Replaces:** Current `DNAAlignmentSection` (minus prediction, which moved to Hero)

**Collapsed state:**
- Contextual phrase: "Esta semana se parece un 78% a la semana del 3 de febrero"
- Mini sparkline: last 4-6 weeks' similarity scores as a small line chart (Canvas)

**Expanded state (tap):**
- Ranked list of most similar historical weeks with DTW scores
- Similarity percentage for each

**Visible only in tier intermediate+.** In basic tier: subtle placeholder "Con más datos podremos detectar semanas similares".

**Data sources:**
- `profile.alignments` → similarity scores, week indices
- Week index → date range conversion (using `profile.nucleotides` dates or record dates)

**Code changes:**
- Rewrite `DNAAlignmentSection.swift` (remove prediction, add sparkline)
- New: `SimilaritySparkline` Canvas component
- Helper to convert week index to human-readable date range

### 7. Footer (inline in profileContent)

**Replaces:** Current disclaimer + `DNATierSection`

**Content:**
- Disclaimer text (as current)
- If not full tier: motivational progress — "Llevas 5 semanas. En 3 semanas más se desbloquea el análisis topológico completo." with mini progress dots (●●●●●○○○)

**Code changes:**
- Remove `DNATierSection` from the section list
- Add inline footer in `profileContent` method of `DNAInsightsView`

## New Shared Components

### ExpandableCard

Reusable wrapper that handles collapsed/expanded state with animation.

```
ExpandableCard(isExpanded: $expanded) {
    // collapsed content
} detail: {
    // expanded content (shown on tap)
}
```

Applies liquid glass, handles tap gesture, animates height change.

### StrengthDotsView

Displays 1-5 filled/empty dots for visual strength indication.

```
StrengthDotsView(level: 3, maxLevel: 5, color: .accent)
```

### MotifHeatmapBar

Canvas-drawn row of colored blocks representing weeks by motif.

```
MotifHeatmapBar(weeks: motifWeekAssignments, colors: motifColorMap)
```

### SimilaritySparkline

Canvas-drawn mini line chart for similarity trend.

```
SimilaritySparkline(values: recentSimilarities)
```

### HealthInsightRules

Deterministic mapping from alert/marker state to actionable text.

```swift
struct HealthInsightRules {
    static func insight(for alertType: AlertType, bundle: Bundle) -> String
    static func proximityWarning(for marker: String, value: Double, threshold: Double, bundle: Bundle) -> String?
}
```

### BasePairDescriptor

Combines synchrony data + expression rules into human-readable phrases.

```swift
struct BasePairDescriptor {
    static func describe(_ pair: BasePairSynchrony, rule: ExpressionRule?, bundle: Bundle) -> (phrase: String, strength: Int, tip: String?)
}
```

## Files Changed

| Action | File | Notes |
|--------|------|-------|
| New | `DNAHeroCard.swift` | Replaces DNAStateSection |
| Modify | `HelixRealityView.swift` | Remove clip, add tier overlay, add week tap callback |
| Rewrite | `DNAHealthSection.swift` | Collapsed/expanded, proximity, persistence, insights |
| Rewrite | `DNAMotifSection.swift` | Human language, heatmap, expandable |
| Rewrite | `DNABasePairsSection.swift` | Cause-effect phrases, strength dots, expandable |
| Rewrite | `DNAAlignmentSection.swift` | Remove prediction, add sparkline, date context |
| Delete | `DNATierSection.swift` | Absorbed into helix overlay + footer |
| Modify | `DNAInsightsView.swift` | New section order, footer, scroll-to coordination |
| New | `ExpandableCard.swift` | Shared collapsible card component |
| New | `StrengthDotsView.swift` | Reusable dot indicator |
| New | `MotifHeatmapBar.swift` | Canvas heatmap row |
| New | `SimilaritySparkline.swift` | Canvas sparkline |
| New | `HealthInsightRules.swift` | Alert → actionable text mapping |
| New | `BasePairDescriptor.swift` | Synchrony → human phrase mapping |
| Modify | `Localizable.xcstrings` | New localization keys for all human-language strings |

## Localization

All new human-facing strings must be added to `Localizable.xcstrings` in both Spanish (primary) and English. Key naming convention follows existing pattern: `dna.section.key`.

New key categories:
- `dna.hero.*` — hero card strings
- `dna.health.insight.*` — actionable health insights
- `dna.health.proximity.*` — proximity warning strings
- `dna.motif.description.*` — motif natural language descriptions
- `dna.basepair.phrase.*` — cause-effect connection phrases
- `dna.alignment.context.*` — temporal similarity phrases
- `dna.tier.motivation.*` — tier progress motivation strings

## Data Dependencies

**New data needed (not currently in SleepDNAProfile):**
- Previous snapshot comparison for trends and alert persistence → fetch from `SDSleepDNASnapshot` via `modelContext`
- Marker thresholds for proximity warnings → reference `HealthMarkerDetector` constants

**Minimal SpiralKit change:** Extract `HealthMarkerDetector` threshold constants as public static properties so the view layer can compute proximity warnings without duplicating magic numbers. No other SpiralKit changes.

### Previous Snapshot Strategy

Multiple sections need the previous `SDSleepDNASnapshot` (Hero for trends, Health for alert persistence). To avoid redundant deserialization of the large `profileJSON` blob, `DNAInsightsView` fetches and decodes the previous snapshot once in `.task {}` and passes the decoded `SleepDNAProfile?` down to sections as a parameter (`previousProfile`).

### Scroll-to Coordination

`DNAInsightsView.profileContent` wraps in a `ScrollViewReader`. Each section gets an `.id()` anchor. The helix's `onWeekTapped` callback triggers `scrollTo` with animation to the relevant section.

### ExpandableCard Animation

Uses `withAnimation(.easeInOut(duration: 0.25))` on the `isExpanded` toggle + conditional content with `.transition(.opacity.combined(with: .move(edge: .top)))`. No `matchedGeometryEffect` — keep it simple and consistent across all sections.

### Localization Interpolation

Spanish cause-effect phrases use `String(format:)` with positional `%1$@` / `%2$@` arguments to handle word order differences from English. All templates in `BasePairDescriptor` and `HealthInsightRules` use format strings, not concatenation.

## Phase 2 (Future)

- Intra-night codon analysis (SleepCodon engine in SpiralKit, new "Arquitectura de la noche" section)
- Foundation Models integration for richer natural language insights
- Interpersonal sleep comparison features
