# DNA Insights UI + Background Task — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Sub-project 3 of 3 (Engine ✅ → 3D Visualization → **Insights UI**)

## Context

The SleepDNA Engine (PR #4) is implemented in SpiralKit with 418 tests but is not yet called from the app. This spec connects it: a background task computes the DNA profile daily, and a narrative "biological mirror" view presents the insights — not as metrics or advice, but as a reflection of the user's circadian biology.

### Design Philosophy

The app is an instrument of **self-awareness**, not a coach. The insights view is a **mirror** that shows the user where they are biologically. No advice, no "you should" — just "this is your body right now."

### Constraints

- Accessed from SpiralTab toolbar (🧬 icon, left side — right side has moon for sleep logging)
- Opens as fullScreenCover — spiral remains the primary view
- Narrative style (large text, natural language) not dashboard/metrics style
- Background computation once/day via BGAppRefreshTask
- On-demand refresh when user opens view and no profile exists for today
- iOS 18+ (SwiftData, existing app minimum)

---

## 1. SleepDNAService

`@Observable @MainActor` service that manages DNA profile lifecycle.

### Properties

```swift
var latestProfile: SleepDNAProfile?
var isComputing: Bool
var lastComputedAt: Date?
var error: String?
```

### Methods

- `loadCachedProfile(context: ModelContext)` — load latest `SDSleepDNASnapshot` from SwiftData, deserialize JSON → `SleepDNAProfile`
- `refreshIfNeeded(store:context:)` — compute only if no snapshot from today. Reads records/events from store, chronotype from store, runs `SleepDNAComputer.compute()`, saves snapshot + BLOSUM to SwiftData.
- `forceRefresh(store:context:)` — compute always (pull-to-refresh)

### Lifecycle

- Created in `spiral_journey_projectApp`, injected via `.environment()`
- On app launch: `loadCachedProfile()` in `.task {}`
- Background task calls `refreshIfNeeded()`
- DNAInsightsView calls `refreshIfNeeded()` on appear if profile is nil

---

## 2. Background Task

### Registration

Add to `BackgroundTaskManager`:
- Identifier: `"com.xaron.spiral.dna-refresh"`
- Type: `BGAppRefreshTask`
- Schedule: daily (earliest begin date = tomorrow 4:00 AM)
- Follow existing pattern in `BackgroundTaskManager.registerTasks(store:)`

### Handler

```
1. Create ModelContext from ModelContainer
2. Read records, events, chronotype, goalDuration from store/SwiftData
3. Call SleepDNAComputer.compute(...)
4. Serialize profile to JSON
5. Save SDSleepDNASnapshot (delete previous if exists)
6. Update SDSleepBLOSUM if tier == .full
7. task.setTaskCompleted(success: true)
8. Schedule next execution
```

### Info.plist

Add `"com.xaron.spiral.dna-refresh"` to `BGTaskSchedulerPermittedIdentifiers` array.

---

## 3. DNAInsightsView — Narrative "Biological Mirror"

FullScreenCover opened from SpiralTab toolbar 🧬 icon (left side).

### Section 1: "Tu ritmo hoy" (DNAStateSection)

- **Large text** colored by state:
  - coherence > 0.7 → green: "Tu cuerpo está **sincronizado**"
  - coherence 0.4-0.7 → yellow: "Tu ritmo está **en transición**"
  - coherence < 0.4 → red: "Tu ritmo está **desalineado**"
- Subtitle: "Coherencia circadiana al X%. Presión homeostática [normal/elevada/baja]."
  - HB < 0.15 → normal, 0.15-0.3 → elevada, > 0.3 → alta
- Animated mini-helix decoration (MiniHelixView) — two intertwined paths with strand colors

### Section 2: "Tu código genético" (DNAMotifSection)

- If motifs exist (tier full):
  - "Llevas N semanas en modo **[motif name]**"
  - "Este patrón se caracteriza por [dominant features description]"
  - If recent mutation: "Esta semana hay una **variación [tipo]** en tu patrón"
    - silent → "silenciosa (sin impacto)"
    - missense → "moderada (afecta tu sueño ligeramente)"
    - nonsense → "significativa (tu patrón se ha roto)"
- If no motifs (tier basic/intermediate):
  - "Aún estoy aprendiendo tu código genético."
  - "Necesito X semanas más para análisis completo."
  - Progress indicator: current weeks / 8 needed

### Section 3: "Déjà vu" (DNAAlignmentSection)

- If alignments exist:
  - "Esta semana se parece al **[date]** ([similarity]% similar)"
  - Subtitle: what happened in remaining days of that historical week
  - If prediction available: "Basándome en eso, esta noche podrías dormir a las **HH:MM**"
- If not enough data:
  - "Aún no tengo suficientes semanas para comparar"

### Section 4: "Tu salud circadiana" (DNAHealthSection)

Only shows relevant markers (not all always). Narrative, not numbers:

- HB > 0.2 → "Tus procesos internos están ligeramente **desincronizados**"
- HCI < 0.8 → "Tu sueño está **fragmentado** — X interrupciones por noche"
- drift > 10 → "Tu hora de dormir se está **desplazando** X min por día"
- RDS abnormal (flat/negative) → "Tu fase REM muestra **deriva inusual**"
- RCE high → "Tus ciclos REM son **irregulares**"
- All good → "Sin alertas — tu ritmo circadiano está **estable**" ✅

### Section 5: "Qué afecta tu sueño" (DNABasePairsSection)

- Top 3 base pairs by PLV
- Natural language: "La **cafeína** tiene un efecto fuerte en tu bedtime"
- Shown only if tier >= intermediate
- If tier basic: hidden entirely

### Section 6: Tier Indicator (DNATierSection)

- Subtle, at bottom
- "Análisis [básico/intermedio/completo] · X semanas de datos"
- If not full: "Análisis completo con Y semanas más"

### Interactions

- Pull-to-refresh → `SleepDNAService.forceRefresh()`
- Dismiss via drag down or X button top-right
- No internal navigation — pure scroll
- Loading state while computing: skeleton/pulse animation

### Localization

- Spanish and English (following existing `LLMContextBuilder` locale pattern)

---

## 4. MiniHelixView

Decorative animated double helix using SwiftUI `Canvas` or `TimelineView`:

- Two intertwined sine curves (purple + orange)
- Gentle rotation/pulse animation
- Height: ~80pt, centered
- Parameters from `DayHelixParams` if available (twist angle affects animation)
- Fallback: default animation if no profile

---

## 5. Integration Points

### SpiralTab.swift

```swift
// Add to toolbar:
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button { showDNAInsights = true } label: {
            Text("🧬")
        }
    }
}
.fullScreenCover(isPresented: $showDNAInsights) {
    DNAInsightsView()
}
```

### spiral_journey_projectApp.swift

- Add `@State private var dnaService = SleepDNAService()`
- Inject: `.environment(dnaService)`
- In `.task {}`: `dnaService.loadCachedProfile(context: modelContainer.mainContext)`

### BackgroundTaskManager.swift

- Register `"com.xaron.spiral.dna-refresh"` task
- Handler calls `SleepDNAService.refreshIfNeeded()`
- Schedule daily at 4:00 AM

### CoachChatView.swift

- Read `dnaService.latestProfile` from environment
- Pass to `LLMContextBuilder.buildSystemPrompt(..., dnaProfile: profile)`

### Info.plist

- Add `"com.xaron.spiral.dna-refresh"` to `BGTaskSchedulerPermittedIdentifiers`

---

## 6. File Structure

### New Files

```
spiral journey project/
  Services/
    SleepDNAService.swift              — @Observable service, profile lifecycle
  Views/
    DNA/
      DNAInsightsView.swift            — fullScreenCover container + scroll
      DNAStateSection.swift            — "Tu ritmo hoy"
      DNAMotifSection.swift            — "Tu código genético"
      DNAAlignmentSection.swift        — "Déjà vu"
      DNAHealthSection.swift           — "Tu salud circadiana"
      DNABasePairsSection.swift        — "Qué afecta tu sueño"
      DNATierSection.swift             — tier indicator
      MiniHelixView.swift              — animated decorative helix
```

### Modified Files

```
spiral journey project/
  Views/Tabs/SpiralTab.swift           — toolbar 🧬 icon + fullScreenCover
  spiral_journey_projectApp.swift      — inject SleepDNAService
  Services/BackgroundTaskManager.swift — register DNA refresh task
  Views/Coach/CoachChatView.swift      — pass dnaProfile to prompt builder
  Info.plist                           — BGTaskSchedulerPermittedIdentifiers
```

---

## 7. Testing Strategy

- **SleepDNAService:** Unit tests for caching logic (load/save snapshot), refresh-if-needed guard, tier determination
- **Background Task:** Manual testing — simulate background launch in Xcode (Debug → Simulate Background Fetch)
- **UI Sections:** Preview-driven development with mock SleepDNAProfile data
- **Integration:** End-to-end: launch app → open 🧬 → see insights → dismiss → verify profile cached

---

## 8. Implementation Order

```
1. SleepDNAService                  — service + caching
2. BackgroundTaskManager integration — daily computation
3. DNAInsightsView + sections        — the narrative UI
4. MiniHelixView                     — animated decoration
5. SpiralTab integration             — toolbar icon
6. CoachChatView integration         — pass profile to prompt
7. Localization (Spanish/English)
```
