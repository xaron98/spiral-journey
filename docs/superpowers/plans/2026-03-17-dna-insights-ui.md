# DNA Insights UI + Background Task — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the SleepDNA Engine to the app via a daily background task and a narrative "biological mirror" view accessible from the spiral.

**Architecture:** `SleepDNAService` manages profile lifecycle (compute, cache, load). Background task runs daily. `DNAInsightsView` opens as fullScreenCover from a 🧬 button in SpiralTab. Six narrative sections scroll vertically — no dashboard metrics, just natural language reflecting the user's circadian state.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, BGTaskScheduler, SpiralKit (SleepDNAComputer)

**Spec:** `docs/superpowers/specs/2026-03-17-dna-insights-ui-design.md`

---

## File Structure

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
  Views/Tabs/SpiralTab.swift           — add 🧬 button + fullScreenCover
  spiral_journey_projectApp.swift      — inject SleepDNAService
  Services/BackgroundTaskManager.swift — register DNA refresh task
  Views/Coach/CoachChatView.swift      — pass dnaProfile to prompt builder
  Info.plist                           — add BGTask identifier
```

---

## Key Existing APIs

```swift
// SleepDNAComputer (actor in SpiralKit) — already implemented
public actor SleepDNAComputer {
    public func compute(
        records: [SleepRecord], events: [CircadianEvent],
        chronotype: ChronotypeResult?, goalDuration: Double,
        period: Double, existingBLOSUM: SleepBLOSUM?
    ) async throws -> SleepDNAProfile
}

// SleepDNAProfile — consolidated output (in SpiralKit)
public struct SleepDNAProfile: Codable, Sendable {
    let nucleotides, sequences, basePairs, motifs, mutations,
        clusters, expressionRules, alignments, prediction,
        scoringMatrix, healthMarkers, helixGeometry, tier,
        computedAt, dataWeeks
}

// SDSleepDNASnapshot — SwiftData cache (already exists)
@Model final class SDSleepDNASnapshot {
    var computedAt: Date, tier: String, dataWeeks: Int
    @Attribute(.externalStorage) var profileJSON: Data?
}

// SDSleepBLOSUM — SwiftData weights (already exists)
@Model final class SDSleepBLOSUM {
    var updatedAt: Date, weightsJSON: String
}

// BackgroundTaskManager pattern:
// - enum with static methods
// - registerTasks(store:) called in App.init()
// - scheduleXxx() called in .task {}
// - handler receives BGProcessingTask, calls setTaskCompleted(success:)

// SpiralTab — no SwiftUI .toolbar, uses in-view ZStack buttons
// - Sleep log button at .topTrailing (moon icon, 48x48)
// - DNA button goes at .topLeading

// LLMContextBuilder already has dnaProfile: SleepDNAProfile? parameter
```

---

## Chunk 1: Service + Background Task (Tasks 1-2)

### Task 1: SleepDNAService

**Files:**
- Create: `spiral journey project/Services/SleepDNAService.swift`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Create SleepDNAService**

```swift
// spiral journey project/Services/SleepDNAService.swift
import Foundation
import SwiftData
import SpiralKit

@Observable
@MainActor
final class SleepDNAService {
    private(set) var latestProfile: SleepDNAProfile?
    private(set) var isComputing: Bool = false
    private(set) var lastComputedAt: Date?
    private(set) var error: String?

    private let computer = SleepDNAComputer()

    /// Load the most recent cached profile from SwiftData
    func loadCachedProfile(context: ModelContext) {
        do {
            var descriptor = FetchDescriptor<SDSleepDNASnapshot>(
                sortBy: [SortDescriptor(\.computedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let snapshot = try context.fetch(descriptor).first,
               let data = snapshot.profileJSON,
               let profile = try? JSONDecoder().decode(SleepDNAProfile.self, from: data) {
                latestProfile = profile
                lastComputedAt = snapshot.computedAt
            }
        } catch {
            print("[SleepDNAService] Failed to load cached profile: \(error)")
        }
    }

    /// Compute only if no snapshot from today
    func refreshIfNeeded(store: SpiralStore, context: ModelContext) async {
        if let last = lastComputedAt, Calendar.current.isDateInToday(last) {
            return // Already computed today
        }
        await computeAndCache(store: store, context: context)
    }

    /// Always compute (pull-to-refresh)
    func forceRefresh(store: SpiralStore, context: ModelContext) async {
        await computeAndCache(store: store, context: context)
    }

    private func computeAndCache(store: SpiralStore, context: ModelContext) async {
        guard !isComputing else { return }
        isComputing = true
        error = nil

        do {
            // Load existing BLOSUM if available
            let existingBLOSUM = loadCachedBLOSUM(context: context)

            let profile = try await computer.compute(
                records: store.records,
                events: store.events,
                chronotype: store.chronotypeResult,
                goalDuration: store.sleepGoal.targetDuration,
                period: store.period,
                existingBLOSUM: existingBLOSUM
            )

            latestProfile = profile
            lastComputedAt = profile.computedAt

            // Cache to SwiftData
            saveSnapshot(profile: profile, context: context)

            // Update BLOSUM if full tier
            if profile.tier == .full {
                saveBLOSUM(profile.scoringMatrix, context: context)
            }
        } catch {
            self.error = error.localizedDescription
            print("[SleepDNAService] Computation failed: \(error)")
        }

        isComputing = false
    }

    private func saveSnapshot(profile: SleepDNAProfile, context: ModelContext) {
        // Delete old snapshots (keep only latest)
        do {
            let old = try context.fetch(FetchDescriptor<SDSleepDNASnapshot>())
            for snapshot in old { context.delete(snapshot) }
        } catch {}

        let data = try? JSONEncoder().encode(profile)
        let snapshot = SDSleepDNASnapshot(
            computedAt: profile.computedAt,
            tier: profile.tier.rawValue,
            dataWeeks: profile.dataWeeks,
            profileJSON: data
        )
        context.insert(snapshot)
        try? context.save()
    }

    private func saveBLOSUM(_ blosum: SleepBLOSUM, context: ModelContext) {
        do {
            let old = try context.fetch(FetchDescriptor<SDSleepBLOSUM>())
            for b in old { context.delete(b) }
        } catch {}

        let json = (try? JSONEncoder().encode(blosum.weights))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        context.insert(SDSleepBLOSUM(updatedAt: Date(), weightsJSON: json))
        try? context.save()
    }

    private func loadCachedBLOSUM(context: ModelContext) -> SleepBLOSUM? {
        guard let stored = try? context.fetch(FetchDescriptor<SDSleepBLOSUM>()).first,
              let data = stored.weightsJSON.data(using: .utf8),
              let weights = try? JSONDecoder().decode([Double].self, from: data),
              weights.count == 16 else { return nil }
        return SleepBLOSUM(weights: weights)
    }
}
```

**Note:** The `store.records` and `store.events` properties may need to be accessed differently. Read SpiralStore to find the exact property names — likely `store.records` (computed from recompute) and `store.events` (the CircadianEvent array). If `records` is not directly accessible, use `store.sleepEpisodes` and convert, or call through the existing recompute pipeline.

- [ ] **Step 2: Inject into app entry point**

In `spiral_journey_projectApp.swift`:

```swift
// Add property alongside other @State services:
@State private var dnaService = SleepDNAService()

// Add environment injection:
.environment(dnaService)

// In .task {} block, after migration and before HealthKit:
dnaService.loadCachedProfile(context: modelContainer.mainContext)
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add SleepDNAService for profile lifecycle management

Loads cached profile from SwiftData, computes via SleepDNAComputer,
caches snapshots and BLOSUM weights. Refreshes daily or on demand."
```

---

### Task 2: Background Task Registration

**Files:**
- Modify: `spiral journey project/Services/BackgroundTaskManager.swift`
- Modify: `spiral journey project/Info.plist`
- Modify: `spiral journey project/spiral_journey_projectApp.swift`

- [ ] **Step 1: Add DNA task to Info.plist**

Add `"com.spiral-journey.dna-refresh"` to the `BGTaskSchedulerPermittedIdentifiers` array:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.spiral-journey.model-retrain</string>
    <string>com.spiral-journey.dna-refresh</string>
</array>
```

- [ ] **Step 2: Add DNA refresh to BackgroundTaskManager**

Follow the existing pattern. Add:

```swift
// New task ID
static let dnaRefreshTaskID = "com.spiral-journey.dna-refresh"

// In registerTasks(store:), add:
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: dnaRefreshTaskID,
    using: nil
) { task in
    Task { @MainActor in
        await handleDNARefreshTask(task as! BGProcessingTask, store: store)
    }
}

// New scheduling method
static func scheduleDNARefresh() {
    let request = BGProcessingTaskRequest(identifier: dnaRefreshTaskID)
    request.earliestBeginDate = Calendar.current.date(
        bySettingHour: 4, minute: 0, second: 0, of: Date()
    )?.addingTimeInterval(86400) // tomorrow 4 AM
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        print("[BGTask] Failed to schedule DNA refresh: \(error)")
    }
}

// Handler
@MainActor
private static func handleDNARefreshTask(_ task: BGProcessingTask, store: SpiralStore) async {
    // Schedule next
    scheduleDNARefresh()

    task.expirationHandler = {
        task.setTaskCompleted(success: false)
    }

    // Get SleepDNAService from... we need to pass it or create a new one
    let dnaService = SleepDNAService()
    // Need ModelContext — create from container
    // This is tricky in background. The handler needs access to ModelContainer.
    // Solution: pass modelContainer to registerTasks alongside store.

    // ... implementation details depend on how ModelContainer is accessible

    task.setTaskCompleted(success: true)
}
```

**Important:** The background handler needs access to `ModelContainer` and `SleepDNAService`. The current `registerTasks(store:)` only receives `store`. Update it to also receive `modelContainer` and `dnaService`:

```swift
static func registerTasks(store: SpiralStore, modelContainer: ModelContainer, dnaService: SleepDNAService)
```

Update the call in `spiral_journey_projectApp.init()` accordingly.

- [ ] **Step 3: Schedule in app entry point**

In `spiral_journey_projectApp.swift` `.task {}`, add:
```swift
BackgroundTaskManager.scheduleDNARefresh()
```

- [ ] **Step 4: Build and commit**

```bash
git commit -m "feat: add daily background task for SleepDNA computation

Registers BGProcessingTask for daily DNA profile refresh at 4 AM.
Handler computes profile via SleepDNAService and caches to SwiftData."
```

---

## Chunk 2: UI Views (Tasks 3-5)

### Task 3: DNAInsightsView + Narrative Sections

**Files:**
- Create: `spiral journey project/Views/DNA/DNAInsightsView.swift`
- Create: `spiral journey project/Views/DNA/DNAStateSection.swift`
- Create: `spiral journey project/Views/DNA/DNAMotifSection.swift`
- Create: `spiral journey project/Views/DNA/DNAAlignmentSection.swift`
- Create: `spiral journey project/Views/DNA/DNAHealthSection.swift`
- Create: `spiral journey project/Views/DNA/DNABasePairsSection.swift`
- Create: `spiral journey project/Views/DNA/DNATierSection.swift`

- [ ] **Step 1: Create DNAInsightsView (container)**

```swift
// spiral journey project/Views/DNA/DNAInsightsView.swift
import SwiftUI
import SpiralKit

struct DNAInsightsView: View {
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(SpiralStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let profile = dnaService.latestProfile {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            DNAStateSection(profile: profile)
                            DNAMotifSection(profile: profile)
                            DNAAlignmentSection(profile: profile)
                            DNAHealthSection(profile: profile)
                            DNABasePairsSection(profile: profile)
                            DNATierSection(profile: profile)
                        }
                        .padding()
                    }
                    .refreshable {
                        await dnaService.forceRefresh(store: store, context: modelContext)
                    }
                } else if dnaService.isComputing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Analizando tu ADN del sueño…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("🧬")
                            .font(.system(size: 48))
                        Text("Tu espejo biológico")
                            .font(.title2.bold())
                        Text("Necesito al menos unos días de datos para empezar el análisis.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("Tu ADN del Sueño")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await dnaService.refreshIfNeeded(store: store, context: modelContext)
            }
        }
    }
}
```

- [ ] **Step 2: Create DNAStateSection — "Tu ritmo hoy"**

```swift
// spiral journey project/Views/DNA/DNAStateSection.swift
import SwiftUI
import SpiralKit

struct DNAStateSection: View {
    let profile: SleepDNAProfile

    private var coherence: Double { profile.healthMarkers.circadianCoherence }
    private var hb: Double { profile.healthMarkers.homeostasisBalance }

    private var stateText: String {
        if coherence > 0.7 { return "sincronizado" }
        if coherence > 0.4 { return "en transición" }
        return "desalineado"
    }

    private var stateColor: Color {
        if coherence > 0.7 { return .green }
        if coherence > 0.4 { return .yellow }
        return .red
    }

    private var pressureText: String {
        if hb < 0.15 { return "normal" }
        if hb < 0.3 { return "elevada" }
        return "alta"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu ritmo hoy")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                Text("Tu cuerpo está ")
                    .font(.title2)
                Text(stateText)
                    .font(.title2.bold())
                    .foregroundStyle(stateColor)
            }

            Text("Coherencia circadiana al \(Int(coherence * 100))%. Presión homeostática \(pressureText).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MiniHelixView(profile: profile)
                .frame(height: 80)
                .padding(.top, 8)
        }
    }
}
```

- [ ] **Step 3: Create DNAMotifSection — "Tu código genético"**

```swift
// spiral journey project/Views/DNA/DNAMotifSection.swift
import SwiftUI
import SpiralKit

struct DNAMotifSection: View {
    let profile: SleepDNAProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu código genético")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let motif = profile.motifs.first {
                Text("Estás en modo ")
                    .font(.title3) +
                Text(motif.name)
                    .font(.title3.bold())
                    .foregroundColor(.purple)

                Text("\(motif.instanceCount) semanas con este patrón en tu historial.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Recent mutation
                if let mutation = profile.mutations.last {
                    let typeText: String = switch mutation.classification {
                    case .silent: "silenciosa (sin impacto)"
                    case .missense: "moderada (afecta tu sueño ligeramente)"
                    case .nonsense: "significativa (tu patrón se ha roto)"
                    }
                    Text("Variación reciente: **\(typeText)**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Aún estoy aprendiendo tu código genético.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                let weeksNeeded = max(0, 8 - profile.dataWeeks)
                if weeksNeeded > 0 {
                    Text("Necesito \(weeksNeeded) semanas más para análisis completo.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    ProgressView(value: Double(profile.dataWeeks), total: 8)
                        .tint(.purple)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Create DNAAlignmentSection — "Déjà vu"**

```swift
// spiral journey project/Views/DNA/DNAAlignmentSection.swift
import SwiftUI
import SpiralKit

struct DNAAlignmentSection: View {
    let profile: SleepDNAProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Déjà vu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let best = profile.alignments.first {
                HStack(spacing: 0) {
                    Text("Esta semana se parece al ")
                        .font(.title3)
                    Text("\(Int(best.similarity * 100))%")
                        .font(.title3.bold())
                        .foregroundStyle(.cyan)
                }

                // Show prediction if available
                if let pred = profile.prediction {
                    let hour = Int(pred.predictedBedtime)
                    let min = Int((pred.predictedBedtime - Double(hour)) * 60)
                    Text("Predicción por alineamiento: bedtime **\(String(format: "%02d:%02d", hour, min))**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Aún no tengo suficientes semanas para comparar.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 5: Create DNAHealthSection — "Tu salud circadiana"**

```swift
// spiral journey project/Views/DNA/DNAHealthSection.swift
import SwiftUI
import SpiralKit

struct DNAHealthSection: View {
    let profile: SleepDNAProfile

    private var markers: HealthMarkers { profile.healthMarkers }

    private var insights: [(String, Color)] {
        var result: [(String, Color)] = []
        if markers.homeostasisBalance > 0.2 {
            result.append(("Tus procesos internos están ligeramente **desincronizados**", .orange))
        }
        if markers.helicalContinuity < 0.8 {
            result.append(("Tu sueño está **fragmentado**", .orange))
        }
        if markers.driftSeverity > 10 {
            result.append(("Tu hora de dormir se está **desplazando** \(Int(markers.driftSeverity)) min por día", .yellow))
        }
        if let rds = markers.remDriftSlope, rds <= 0 {
            result.append(("Tu fase REM muestra **deriva inusual**", .orange))
        }
        if let rce = markers.remClusterEntropy, rce > 1.5 {
            result.append(("Tus ciclos REM son **irregulares**", .orange))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu salud circadiana")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if insights.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Sin alertas — tu ritmo circadiano está **estable**")
                        .font(.title3)
                }
            } else {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top) {
                        Circle()
                            .fill(insight.1)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        Text(LocalizedStringKey(insight.0))
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Create DNABasePairsSection — "Qué afecta tu sueño"**

```swift
// spiral journey project/Views/DNA/DNABasePairsSection.swift
import SwiftUI
import SpiralKit

struct DNABasePairsSection: View {
    let profile: SleepDNAProfile

    // Feature index → readable name
    private let featureNames: [Int: String] = [
        8: "cafeína", 9: "ejercicio", 10: "alcohol",
        11: "melatonina", 12: "estrés", 13: "fin de semana",
        14: "deriva horaria", 15: "calidad del sueño"
    ]

    private let sleepFeatureNames: [Int: String] = [
        0: "hora de dormir", 2: "hora de despertar",
        4: "duración", 5: "presión del sueño",
        6: "acrofase", 7: "estabilidad circadiana"
    ]

    var body: some View {
        if profile.tier != .basic, !profile.basePairs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Qué afecta tu sueño")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(Array(profile.basePairs.prefix(3).enumerated()), id: \.offset) { _, pair in
                    let context = featureNames[pair.contextFeatureIndex] ?? "factor \(pair.contextFeatureIndex)"
                    let sleep = sleepFeatureNames[pair.sleepFeatureIndex] ?? "sueño"
                    let strength = pair.plv > 0.7 ? "fuerte" : "moderado"

                    Text("La **\(context)** tiene un efecto **\(strength)** en tu \(sleep)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 7: Create DNATierSection**

```swift
// spiral journey project/Views/DNA/DNATierSection.swift
import SwiftUI
import SpiralKit

struct DNATierSection: View {
    let profile: SleepDNAProfile

    private var tierName: String {
        switch profile.tier {
        case .basic: "básico"
        case .intermediate: "intermedio"
        case .full: "completo"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Análisis \(tierName) · \(profile.dataWeeks) semanas de datos")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if profile.tier != .full {
                let needed = max(0, 8 - profile.dataWeeks)
                Text("Análisis completo con \(needed) semanas más")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
}
```

- [ ] **Step 8: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 9: Commit**

```bash
git commit -m "feat: add DNAInsightsView with 6 narrative sections

Biological mirror UI: circadian state, motif pattern, déjà vu
alignment, health markers, base pairs, tier indicator. Pull-to-refresh.
Loading and empty states."
```

---

### Task 4: MiniHelixView

**Files:**
- Create: `spiral journey project/Views/DNA/MiniHelixView.swift`

- [ ] **Step 1: Create animated decorative helix**

```swift
// spiral journey project/Views/DNA/MiniHelixView.swift
import SwiftUI
import SpiralKit

struct MiniHelixView: View {
    let profile: SleepDNAProfile?
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let midY = h / 2
                let amplitude = h * 0.35

                // Strand 1 (purple — sleep)
                var path1 = Path()
                var path2 = Path()

                for x in stride(from: 0, through: w, by: 2) {
                    let t = (x / w) * 4 * .pi + phase
                    let y1 = midY + sin(t) * amplitude
                    let y2 = midY + sin(t + .pi) * amplitude // anti-phase

                    if x == 0 {
                        path1.move(to: CGPoint(x: x, y: y1))
                        path2.move(to: CGPoint(x: x, y: y2))
                    } else {
                        path1.addLine(to: CGPoint(x: x, y: y1))
                        path2.addLine(to: CGPoint(x: x, y: y2))
                    }
                }

                context.stroke(path1, with: .color(.purple.opacity(0.6)),
                             lineWidth: 2.5)
                context.stroke(path2, with: .color(.orange.opacity(0.6)),
                             lineWidth: 2.5)

                // Base pair connectors (every ~50pt)
                for x in stride(from: 25, through: w - 25, by: 50) {
                    let t = (x / w) * 4 * .pi + phase
                    let y1 = midY + sin(t) * amplitude
                    let y2 = midY + sin(t + .pi) * amplitude

                    var connector = Path()
                    connector.move(to: CGPoint(x: x, y: y1))
                    connector.addLine(to: CGPoint(x: x, y: y2))
                    context.stroke(connector,
                                 with: .color(.gray.opacity(0.2)),
                                 style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .onChange(of: timeline.date) { _, _ in
                phase += 0.02
            }
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git commit -m "feat: add animated MiniHelixView decoration

Canvas-based double helix with gentle animation.
Purple (sleep) and orange (context) strands with base pair connectors."
```

---

### Task 5: SpiralTab Integration

**Files:**
- Modify: `spiral journey project/Views/Tabs/SpiralTab.swift`

- [ ] **Step 1: Add 🧬 button and fullScreenCover**

In SpiralTab, add a state variable and the button. The existing layout uses `ZStack` with overlay buttons. Add the DNA button at `.topLeading`:

```swift
// Add state:
@State private var showDNAInsights = false

// Add button in the overlay ZStack, positioned at .topLeading:
// (near the existing sleep log button which is at .topTrailing)
Button {
    showDNAInsights = true
} label: {
    Text("🧬")
        .font(.system(size: 24))
        .frame(width: 48, height: 48)
        .background(.ultraThinMaterial, in: Circle())
}

// Add fullScreenCover:
.fullScreenCover(isPresented: $showDNAInsights) {
    DNAInsightsView()
}
```

**Important:** Read SpiralTab.swift to find the exact ZStack structure and where other overlay buttons are positioned. Place the DNA button symmetrically opposite the sleep log button.

- [ ] **Step 2: Build and commit**

```bash
git commit -m "feat: add 🧬 toolbar button in SpiralTab

Opens DNAInsightsView as fullScreenCover. Button at top-leading,
symmetric with sleep log button at top-trailing."
```

---

## Chunk 3: Integration + Polish (Tasks 6-7)

### Task 6: CoachChatView Integration

**Files:**
- Modify: `spiral journey project/Views/Coach/CoachChatView.swift`

- [ ] **Step 1: Pass dnaProfile to prompt builder**

In CoachChatView, the system prompt is built somewhere before calling `provider.generate()`. Find where `LLMContextBuilder.buildSystemPrompt()` is called and add the DNA profile:

```swift
// Read DNA service from environment:
@Environment(SleepDNAService.self) private var dnaService

// Where the prompt is built, add dnaProfile parameter:
let systemPrompt = LLMContextBuilder.buildSystemPrompt(
    analysis: analysis,
    goal: store.sleepGoal,
    records: records,
    capability: provider?.requiresDownload == true ? .compact : .rich,
    prediction: store.latestPrediction,
    modelAccuracy: nil,
    dnaProfile: dnaService.latestProfile  // ADD THIS
)
```

The `dnaProfile` parameter already exists on `buildSystemPrompt` (added in the engine PR). We just need to pass it.

- [ ] **Step 2: Build and commit**

```bash
git commit -m "feat: inject SleepDNA profile into coach system prompt

Coach now has access to motif patterns, health markers, and
alignment data for richer contextual responses."
```

---

### Task 7: Localization (8 languages)

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`
- Modify: All DNA view sections to use localized string keys

The app supports 8 languages via `AppLanguage` enum: **en, es, ca, de, fr, zh, ja, ar** (plus system auto-detect).

- [ ] **Step 1: Replace hardcoded Spanish strings with localized keys in all DNA sections**

All hardcoded text in DNA views should use `String(localized:)` or SwiftUI `Text("key")` with entries in `Localizable.xcstrings`. Example:

```swift
// BEFORE:
Text("Tu ritmo hoy")

// AFTER:
Text("dna.state.title")  // key in Localizable.xcstrings
```

**Keys to create for all 8 languages:**

| Key | en | es | ca | de | fr | zh | ja | ar |
|-----|----|----|----|----|----|----|----|----|
| `dna.title` | Your Sleep DNA | Tu ADN del Sueño | El teu ADN del Son | Deine Schlaf-DNA | Ton ADN du Sommeil | 你的睡眠DNA | あなたの睡眠DNA | حمضك النووي للنوم |
| `dna.state.title` | Your rhythm today | Tu ritmo hoy | El teu ritme avui | Dein Rhythmus heute | Ton rythme aujourd'hui | 你今天的节奏 | 今日のリズム | إيقاعك اليوم |
| `dna.state.synchronized` | synchronized | sincronizado | sincronitzat | synchronisiert | synchronisé | 同步的 | 同期済み | متزامن |
| `dna.state.transition` | in transition | en transición | en transició | im Übergang | en transition | 过渡中 | 移行中 | في مرحلة انتقالية |
| `dna.state.misaligned` | misaligned | desalineado | desalineat | fehlausgerichtet | désaligné | 失调 | ずれている | غير متوازن |
| `dna.state.body` | Your body is | Tu cuerpo está | El teu cos està | Dein Körper ist | Ton corps est | 你的身体处于 | あなたの体は | جسمك |
| `dna.state.coherence` | Circadian coherence at %@%%. Homeostatic pressure %@. | Coherencia circadiana al %@%%. Presión homeostática %@. | Coherència circadiana al %@%%. Pressió homeostàtica %@. | Zirkadiane Kohärenz bei %@%%. Homöostatischer Druck %@. | Cohérence circadienne à %@%%. Pression homéostatique %@. | 昼夜节律一致性 %@%%。稳态压力%@。| 概日リズム一貫性 %@%%。恒常性圧力%@。| التماسك اليومي %@٪٪. الضغط التوازني %@. |
| `dna.pressure.normal` | normal | normal | normal | normal | normale | 正常 | 正常 | طبيعي |
| `dna.pressure.elevated` | elevated | elevada | elevada | erhöht | élevée | 升高 | 上昇 | مرتفع |
| `dna.pressure.high` | high | alta | alta | hoch | haute | 高 | 高い | عالي |
| `dna.motif.title` | Your genetic code | Tu código genético | El teu codi genètic | Dein genetischer Code | Ton code génétique | 你的基因密码 | あなたの遺伝コード | شفرتك الجينية |
| `dna.motif.active` | You're in %@ mode | Estás en modo %@ | Estàs en mode %@ | Du bist im %@-Modus | Tu es en mode %@ | 你处于%@模式 | %@モードです | أنت في وضع %@ |
| `dna.motif.learning` | Still learning your genetic code. | Aún estoy aprendiendo tu código genético. | Encara estic aprenent el teu codi genètic. | Lerne noch deinen genetischen Code. | J'apprends encore ton code génétique. | 仍在学习你的基因密码。| まだ遺伝コードを学習中です。| لا يزال يتعلم شفرتك الجينية. |
| `dna.motif.weeks_needed` | Need %@ more weeks for full analysis. | Necesito %@ semanas más para análisis completo. | Necessito %@ setmanes més per a l'anàlisi completa. | Noch %@ Wochen für vollständige Analyse nötig. | Besoin de %@ semaines de plus pour l'analyse complète. | 需要再%@周才能完成分析。| 完全な分析にはあと%@週間必要です。| تحتاج %@ أسابيع إضافية للتحليل الكامل. |
| `dna.dejavu.title` | Déjà vu | Déjà vu | Déjà vu | Déjà vu | Déjà vu | 似曾相识 | デジャヴ | ديجا فو |
| `dna.dejavu.similar` | This week resembles %@%% | Esta semana se parece al %@%% | Aquesta setmana s'assembla al %@%% | Diese Woche ähnelt zu %@%% | Cette semaine ressemble à %@%% | 本周相似度 %@%% | 今週の類似度 %@%% | هذا الأسبوع يشبه %@٪٪ |
| `dna.dejavu.not_enough` | Not enough weeks to compare yet. | Aún no tengo suficientes semanas para comparar. | Encara no tinc prou setmanes per comparar. | Noch nicht genug Wochen zum Vergleichen. | Pas encore assez de semaines pour comparer. | 还没有足够的周数进行比较。| 比較するのに十分な週数がありません。| لا توجد أسابيع كافية للمقارنة بعد. |
| `dna.health.title` | Your circadian health | Tu salud circadiana | La teva salut circadiana | Deine zirkadiane Gesundheit | Ta santé circadienne | 你的昼夜节律健康 | あなたの概日リズムの健康 | صحتك اليومية |
| `dna.health.stable` | No alerts — your circadian rhythm is stable | Sin alertas — tu ritmo circadiano está estable | Sense alertes — el teu ritme circadià és estable | Keine Alarme — dein zirkadianer Rhythmus ist stabil | Pas d'alertes — ton rythme circadien est stable | 无警报——你的昼夜节律稳定 | アラートなし——概日リズムは安定しています | لا تنبيهات — إيقاعك اليومي مستقر |
| `dna.basepairs.title` | What affects your sleep | Qué afecta tu sueño | Què afecta el teu son | Was deinen Schlaf beeinflusst | Ce qui affecte ton sommeil | 什么影响你的睡眠 | 何があなたの睡眠に影響するか | ما يؤثر على نومك |
| `dna.tier.basic` | basic | básico | bàsic | grundlegend | basique | 基础 | 基本 | أساسي |
| `dna.tier.intermediate` | intermediate | intermedio | intermedi | mittel | intermédiaire | 中级 | 中級 | متوسط |
| `dna.tier.full` | complete | completo | complet | vollständig | complet | 完整 | 完全 | كامل |

- [ ] **Step 2: Add all keys to `Localizable.xcstrings`**

Read the existing `Localizable.xcstrings` to understand the JSON format, then add all the DNA keys with translations for all 8 languages.

- [ ] **Step 3: Update all DNA section views to use the localized keys instead of hardcoded text**

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: localize DNA Insights in 8 languages

English, Spanish, Catalan, German, French, Chinese, Japanese, Arabic.
All narrative sections use Localizable.xcstrings keys."
```

---

## Final Verification

After all tasks complete:

- [ ] `cd SpiralKit && swift test` — existing 418 tests still pass
- [ ] `xcodebuild build -scheme "spiral journey project" ...` — iOS builds
- [ ] `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS` — Watch builds
- [ ] Run in simulator: tap 🧬 → see insights view → dismiss → verify no crash
- [ ] Pull-to-refresh in insights view → triggers recomputation
- [ ] Verify background task registered: Debug → Simulate Background Fetch in Xcode
