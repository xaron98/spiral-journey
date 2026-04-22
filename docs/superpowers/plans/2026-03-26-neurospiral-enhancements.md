# NeuroSpiral Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor NeuroSpiralView into a dashboard hub with hero metrics, add per-night history, animated trajectory, CSV export with Python loader, and Watch minicard.

**Architecture:** Hub pattern — NeuroSpiralView computes all analyses and passes results to detail views via NavigationLink. Watch receives summary via WatchConnectivity applicationContext (same pattern as existing data sync). Python loader in `src/data/watch_loader.py` consumes the CSV export.

**Tech Stack:** SwiftUI (Canvas, TimelineView, ShareLink), SpiralGeometry package, WatchConnectivity, Python (pandas, numpy, dataclasses)

---

## File Map

### iOS — Create
| File | Responsibility |
|------|---------------|
| `Views/DNA/NeuroSpiralTorusDetailView.swift` | Full torus scatter with legend + vertex residence table |
| `Views/DNA/NeuroSpiralHistoryView.swift` | Per-night sparklines + night list |
| `Views/DNA/NeuroSpiralTrajectoryView.swift` | Animated trajectory Canvas with playback controls |
| `Views/DNA/NeuroSpiralExportView.swift` | CSV generation + ShareLink |

### iOS — Modify
| File | Change |
|------|--------|
| `Views/DNA/NeuroSpiralView.swift` | Refactor to hub dashboard, add perNightAnalyses, retain samples, persist baseline, write Watch data |
| `Services/WatchConnectivityManager.swift` | Add neurospiral data to applicationContext |

### Watch — Create
| File | Responsibility |
|------|---------------|
| `Spiral Watch App Watch App/WatchNeuroSpiralCard.swift` | Stability + dominant state display |

### Watch — Modify
| File | Change |
|------|--------|
| `Spiral Watch App Watch App/ContentView.swift` | Add tab 4 for WatchNeuroSpiralCard |
| `Spiral Watch App Watch App/WatchStore.swift` | Read neurospiral data from context |

### Python — Create
| File | Responsibility |
|------|---------------|
| `neurospiral/src/data/watch_loader.py` | Load CSV from iOS, return WatchRecord |

### Python — Modify
| File | Change |
|------|--------|
| `neurospiral/scripts/publish_validate.py` | Add `--input-type watch --watch-csv` flag |

### Localization — Modify
| File | Change |
|------|--------|
| `spiral journey project/Localizable.xcstrings` | Add ~25 new neurospiral.hub/history/trajectory/export keys × 8 langs |

---

### Task 1: Extract shared types and helpers into hub header

**Files:**
- Modify: `spiral journey project/Views/DNA/NeuroSpiralView.swift`

- [ ] **Step 1: Add NightAnalysis type and new @State properties**

At the top of the file, after the existing `@State` properties (line 21), add:

```swift
    @State private var perNightAnalyses: [NightAnalysis] = []
    @State private var retainedSamples: [WearableSleepSample] = []
```

After the closing `}` of `NeuroSpiralView` (before end of file), add:

```swift
struct NightAnalysis: Identifiable {
    let id: UUID
    let date: Date
    let stability: Double
    let dominantVertexIdx: Int
    let dominantVertexCode: String
    let omega1: Double
    let omega2: Double
    let windingRatio: Double?
    let transitionCount: Int
    let sampleCount: Int
}
```

- [ ] **Step 2: Update loadAndAnalyze to retain samples, compute per-night, persist baseline, write Watch data**

Replace the `loadAndAnalyze()` method (lines 522-561) with:

```swift
    private func loadAndAnalyze() async {
        isLoading = true
        let records = store.records
        let hrvData = store.hrvData

        guard records.count >= 3 else {
            analysis = nil
            isLoading = false
            return
        }

        let allSamples = buildSamplesFromRecords(records, hrvData: hrvData)

        guard !allSamples.isEmpty else {
            analysis = nil
            isLoading = false
            return
        }

        // Load or create baseline
        var mapper = WearableTo4DMapper()
        let defaults = UserDefaults(suiteName: "group.xaron.spiral-journey-project")
        if let data = defaults?.data(forKey: "neurospiral-baseline"),
           let saved = try? JSONDecoder().decode(WearableTo4DMapper.PersonalBaseline.self, from: data) {
            mapper.baseline = saved
        } else if !hrvData.isEmpty {
            let meanHRV = hrvData.map(\.meanSDNN).reduce(0, +) / Double(hrvData.count)
            mapper.baseline.hrvMean = meanHRV
            mapper.baseline.hrvStd = hrvStandardDeviation(hrvData.map(\.meanSDNN))
        }

        let result = mapper.analyzeNight(allSamples)

        // Per-night analyses
        let nights = buildPerNightAnalyses(records: records, hrvData: hrvData, mapper: mapper)

        // Persist baseline
        if let encoded = try? JSONEncoder().encode(mapper.baseline) {
            defaults?.set(encoded, forKey: "neurospiral-baseline")
        }

        // Write Watch data
        writeWatchData(analysis: result, defaults: defaults)

        analysis = result
        perNightAnalyses = nights
        retainedSamples = allSamples
        isLoading = false
    }
```

- [ ] **Step 3: Add buildPerNightAnalyses and writeWatchData methods**

After `hrvStandardDeviation` (line 647), before the closing `}` of the struct, add:

```swift
    private func buildPerNightAnalyses(
        records: [SleepRecord],
        hrvData: [NightlyHRV],
        mapper: WearableTo4DMapper
    ) -> [NightAnalysis] {
        let recentRecords = records.suffix(14)
        var results: [NightAnalysis] = []

        for record in recentRecords {
            let nightSamples = buildSamplesFromSingleRecord(record, hrvData: hrvData)
            guard nightSamples.count >= 10 else { continue }

            let nightResult = mapper.analyzeNight(nightSamples)
            let vertex = nightResult.residence.dominantVertex

            results.append(NightAnalysis(
                id: record.id,
                date: record.date,
                stability: nightResult.residence.stabilityScore,
                dominantVertexIdx: vertex.index,
                dominantVertexCode: formatCode(vertex.code),
                omega1: nightResult.omega1Mean,
                omega2: nightResult.omega2Mean,
                windingRatio: nightResult.windingRatio,
                transitionCount: nightResult.residence.transitionCount,
                sampleCount: nightSamples.count
            ))
        }

        return results
    }

    private func buildSamplesFromSingleRecord(
        _ record: SleepRecord,
        hrvData: [NightlyHRV]
    ) -> [WearableSleepSample] {
        let calendar = Calendar.current
        var hrvByDate: [String: Double] = [:]
        for hrv in hrvData {
            let key = ISO8601DateFormatter().string(from: calendar.startOfDay(for: hrv.date))
            hrvByDate[key] = hrv.meanSDNN
        }

        let dateKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: record.date))
        let nightHRV = hrvByDate[dateKey] ?? 50.0
        var samples: [WearableSleepSample] = []

        for phase in record.phases {
            let sleepPhase = mapPhase(phase.phase)
            let (hrvMod, hrMod, motionMod) = phaseModulation(sleepPhase)

            for epoch in 0..<30 {
                let secondsOffset = phase.hour * 3600 + Double(epoch) * 30
                let timestamp = calendar.startOfDay(for: record.date)
                    .addingTimeInterval(secondsOffset)

                let jitter = Double.random(in: -0.1...0.1)
                samples.append(WearableSleepSample(
                    hrv: max(5, nightHRV * hrvMod + jitter * 10),
                    heartRate: max(40, 65 * hrMod + jitter * 5),
                    motionIntensity: max(0, motionMod + Double.random(in: -0.02...0.02)),
                    sleepStage: sleepPhase,
                    timestamp: timestamp
                ))
            }
        }
        return samples
    }

    private func writeWatchData(analysis: SleepTrajectoryAnalysis, defaults: UserDefaults?) {
        let vertex = analysis.residence.dominantVertex
        let watchData: [String: Any] = [
            "neurospiral_date": Date().timeIntervalSince1970,
            "neurospiral_stability": analysis.residence.stabilityScore,
            "neurospiral_dominant_idx": vertex.index,
            "neurospiral_dominant_code": formatCode(vertex.code),
            "neurospiral_winding": analysis.windingRatio ?? -1.0,
            "neurospiral_transitions": analysis.residence.transitionCount,
        ]
        defaults?.set(watchData, forKey: "neurospiral-last-night")
    }
```

- [ ] **Step 4: Build and verify compilation**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED

---

### Task 2: Refactor hub body to dashboard layout

**Files:**
- Modify: `spiral journey project/Views/DNA/NeuroSpiralView.swift`

- [ ] **Step 1: Replace the body content with dashboard hub**

Replace the `body` var (lines 23-72) with:

```swift
    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerCard

                        if isLoading {
                            loadingState
                        } else if let analysis {
                            heroMetricsRow(analysis)
                            miniTorusCard(analysis)
                            actionButtonsRow
                            compactDominantCard(analysis)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(loc("neurospiral.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingInfo = true } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(SpiralColors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingInfo) {
                neuroSpiralInfoView
            }
            .task {
                await loadAndAnalyze()
            }
        }
    }
```

- [ ] **Step 2: Add hero metrics row**

After the `headerCard` computed property, add:

```swift
    // MARK: - Hero Metrics

    private func heroMetricsRow(_ analysis: SleepTrajectoryAnalysis) -> some View {
        HStack(spacing: 12) {
            heroMetric(
                value: String(format: "%.0f%%", analysis.residence.stabilityScore * 100),
                label: loc("neurospiral.hub.stability"),
                color: analysis.residence.stabilityScore > 0.6 ? SpiralColors.good : .orange
            )
            heroMetric(
                value: "V\(String(format: "%02d", analysis.residence.dominantVertex.index))",
                label: loc("neurospiral.hub.dominant"),
                color: .purple
            )
            heroMetric(
                value: analysis.windingRatio.map { String(format: "%.2f", $0) } ?? "—",
                label: "ω₁/ω₂",
                color: .teal
            )
        }
    }

    private func heroMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.monospaced().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
```

- [ ] **Step 3: Add mini torus card (tappable)**

```swift
    // MARK: - Mini Torus

    private func miniTorusCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        NavigationLink {
            NeuroSpiralTorusDetailView(analysis: analysis)
        } label: {
            torusCanvas(analysis, height: 200)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func torusCanvas(_ analysis: SleepTrajectoryAnalysis, height: CGFloat) -> some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let padX: CGFloat = 16, padY: CGFloat = 16
            let plotW = w - 2 * padX, plotH = h - 2 * padY

            // Grid
            let gridColor = Color.secondary.opacity(0.12)
            for i in 0...4 {
                let x = padX + CGFloat(i) / 4.0 * plotW
                let y = padY + CGFloat(i) / 4.0 * plotH
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) }, with: .color(gridColor), lineWidth: 0.5)
                context.stroke(Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) }, with: .color(gridColor), lineWidth: 0.5)
            }

            // Trajectory
            for point in analysis.trajectory {
                let (theta, phi) = CliffordTorus.angles(of: point)
                let x = padX + ((theta + .pi) / (2 * .pi)) * plotW
                let y = padY + ((phi + .pi) / (2 * .pi)) * plotH
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.purple.opacity(0.5)))
            }

            // Vertices
            for vertex in Tesseract.vertices {
                let (vt, vp) = vertex.torusAngles
                let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
                let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
                let isDominant = vertex.index == analysis.residence.dominantVertex.index
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(isDominant ? .green : .orange.opacity(0.6)))
            }
        }
        .frame(height: height)
    }
```

- [ ] **Step 4: Add action buttons row**

```swift
    // MARK: - Action Buttons

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            if let analysis {
                actionButton(icon: "clock.arrow.circlepath", label: loc("neurospiral.hub.history")) {
                    NeuroSpiralHistoryView(nights: perNightAnalyses)
                }
                actionButton(icon: "point.3.connected.trianglepath.dotted", label: loc("neurospiral.hub.trajectory")) {
                    NeuroSpiralTrajectoryView(analysis: analysis)
                }
                actionButton(icon: "square.and.arrow.up", label: loc("neurospiral.hub.export")) {
                    NeuroSpiralExportView(samples: retainedSamples, analysis: analysis)
                }
            }
        }
    }

    private func actionButton<Destination: View>(icon: String, label: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(SpiralColors.accent)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 5: Add compact dominant state card**

```swift
    // MARK: - Compact Dominant

    private func compactDominantCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        let code = analysis.residence.dominantVertex.code
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc("neurospiral.dominant.title"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text("V\(String(format: "%02d", analysis.residence.dominantVertex.index)) \(formatCode(code))")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.purple)
            }
            dimensionRow(loc("neurospiral.dim.autonomic"), value: code.x, positive: loc("neurospiral.dim.high"), negative: loc("neurospiral.dim.low"))
            dimensionRow(loc("neurospiral.dim.stillness"), value: code.y, positive: loc("neurospiral.dim.quiet"), negative: loc("neurospiral.dim.movement"))
            dimensionRow(loc("neurospiral.dim.cardiac"), value: code.z, positive: loc("neurospiral.dim.slow"), negative: loc("neurospiral.dim.fast"))
            dimensionRow(loc("neurospiral.dim.circadian"), value: code.w, positive: loc("neurospiral.dim.diurnal"), negative: loc("neurospiral.dim.nocturnal"))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
```

- [ ] **Step 6: Remove old card methods that moved to detail views**

Delete these methods from NeuroSpiralView (they will live in TorusDetailView):
- `torusProjectionView(_:)` (the old full-size version with legend)
- `vertexResidenceCard(_:)`
- `oscillatorCard(_:)`
- `transitionCard(_:)`
- `dominantStateCard(_:)` (replaced by `compactDominantCard`)
- `legendDot(_:color:)`
- `oscillatorColumn(symbol:value:label:color:)`

Keep: `headerCard`, `loadingState`, `emptyState`, `heroMetricsRow`, `miniTorusCard`, `torusCanvas`, `actionButtonsRow`, `actionButton`, `compactDominantCard`, `dimensionRow`, `formatCode`, `loc`, `neuroSpiralInfoView`, `infoSection`, all data loading methods.

- [ ] **Step 7: Build and verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: Will fail — detail views don't exist yet. Proceed to Task 3.

---

### Task 3: Create TorusDetailView

**Files:**
- Create: `spiral journey project/Views/DNA/NeuroSpiralTorusDetailView.swift`

- [ ] **Step 1: Create the full torus detail view**

```swift
import SwiftUI
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import struct SpiralGeometry.TesseractVertex
import struct SpiralGeometry.VertexResidence
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralTorusDetailView: View {
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                torusProjection
                legendRow
                vertexResidenceCard
                oscillatorCard
                transitionCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.torus.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Torus Projection

    private var torusProjection: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let padX: CGFloat = 20, padY: CGFloat = 20
            let plotW = w - 2 * padX, plotH = h - 2 * padY

            let gridColor = Color.secondary.opacity(0.15)
            for i in 0...4 {
                let x = padX + CGFloat(i) / 4.0 * plotW
                let y = padY + CGFloat(i) / 4.0 * plotH
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) }, with: .color(gridColor), lineWidth: 0.5)
                context.stroke(Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) }, with: .color(gridColor), lineWidth: 0.5)
            }

            for point in analysis.trajectory {
                let (theta, phi) = CliffordTorus.angles(of: point)
                let x = padX + ((theta + .pi) / (2 * .pi)) * plotW
                let y = padY + ((phi + .pi) / (2 * .pi)) * plotH
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.purple.opacity(0.5)))
            }

            for vertex in Tesseract.vertices {
                let (vt, vp) = vertex.torusAngles
                let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
                let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
                let isDominant = vertex.index == analysis.residence.dominantVertex.index
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(isDominant ? .green : .orange.opacity(0.6)))
            }
        }
        .frame(height: 280)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            Label(loc("neurospiral.legend.samples"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.purple)
            Label(loc("neurospiral.legend.vertices"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.orange)
            Label(loc("neurospiral.legend.dominant"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.green)
        }
    }

    // MARK: - Vertex Residence

    private var vertexResidenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("neurospiral.residence.title"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            let sorted = analysis.vertexFractions.sorted { $0.value > $1.value }.prefix(5)
            ForEach(Array(sorted), id: \.key) { vertexIdx, fraction in
                let vertex = Tesseract.vertices[vertexIdx]
                HStack {
                    Text("V\(String(format: "%02d", vertexIdx))")
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Text(formatCode(vertex.code))
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SpiralColors.text)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.purple.opacity(0.3))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(width: 60, height: 8)
                }
            }

            HStack {
                Label(loc("neurospiral.stability"), systemImage: "waveform.path")
                    .font(.caption).foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(String(format: "%.0f%%", analysis.residence.stabilityScore * 100))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(analysis.residence.stabilityScore > 0.6 ? SpiralColors.good : .orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Oscillators

    private var oscillatorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("neurospiral.oscillators.title"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            HStack(spacing: 20) {
                oscColumn("ω₁", value: String(format: "%.3f", analysis.omega1Mean), label: loc("neurospiral.process_s"), color: .purple)
                Divider().frame(height: 50)
                oscColumn("ω₂", value: String(format: "%.3f", analysis.omega2Mean), label: loc("neurospiral.process_c"), color: .teal)
                Divider().frame(height: 50)
                oscColumn("ω₁/ω₂", value: analysis.windingRatio.map { String(format: "%.2f", $0) } ?? "—", label: "Winding", color: .orange)
            }

            Text(loc("neurospiral.oscillators.explanation"))
                .font(.caption2).foregroundStyle(SpiralColors.muted)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func oscColumn(_ symbol: String, value: String, label: String, color: Color) -> some View {
        VStack {
            Text(symbol).font(.caption2).foregroundStyle(SpiralColors.muted)
            Text(value).font(.title3.monospaced().weight(.medium)).foregroundStyle(SpiralColors.text)
            Text(label).font(.caption2).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transitions

    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("neurospiral.transitions.title"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(SpiralColors.text)
                Spacer()
                Text(String(format: loc("neurospiral.transitions.count"), analysis.residence.transitionCount))
                    .font(.caption).foregroundStyle(SpiralColors.muted)
            }

            let topEdges = analysis.edgeTraversals.sorted { $0.value > $1.value }.prefix(5)
            if topEdges.isEmpty {
                Text(loc("neurospiral.transitions.none"))
                    .font(.caption).foregroundStyle(SpiralColors.muted)
            } else {
                ForEach(Array(topEdges), id: \.key) { edge, count in
                    HStack {
                        Text(edge).font(.caption.monospaced()).foregroundStyle(SpiralColors.text)
                        Spacer()
                        Text("×\(count)").font(.caption.weight(.medium)).foregroundStyle(SpiralColors.muted)
                    }
                }
            }

            Text(loc("neurospiral.transitions.explanation"))
                .font(.caption2).foregroundStyle(SpiralColors.muted)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "[\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))]"
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: Will fail — HistoryView, TrajectoryView, ExportView still missing. Continue.

---

### Task 4: Create HistoryView

**Files:**
- Create: `spiral journey project/Views/DNA/NeuroSpiralHistoryView.swift`

- [ ] **Step 1: Create the history view with sparklines and night list**

```swift
import SwiftUI
import SpiralKit

struct NeuroSpiralHistoryView: View {
    let nights: [NightAnalysis]

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if nights.count >= 2 {
                    stabilitySparkline
                    windingSparkline
                }
                nightList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.history.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Stability Sparkline

    private var stabilitySparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.history.stability_trend"))
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Canvas { context, size in
                let w = size.width, h = size.height
                let pad: CGFloat = 4
                let values = nights.map(\.stability)
                guard values.count >= 2 else { return }

                let maxVal = 1.0
                let points: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: pad + CGFloat(i) / CGFloat(values.count - 1) * (w - 2 * pad),
                        y: pad + (1 - v / maxVal) * (h - 2 * pad)
                    )
                }

                // Threshold line at 60%
                let threshY = pad + (1 - 0.6) * (h - 2 * pad)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: pad, y: threshY)); p.addLine(to: CGPoint(x: w - pad, y: threshY)) },
                    with: .color(.orange.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                // Line
                var path = Path()
                path.move(to: points[0])
                for pt in points.dropFirst() { path.addLine(to: pt) }
                context.stroke(path, with: .color(SpiralColors.good), lineWidth: 2)

                // Dots
                for pt in points {
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(SpiralColors.good))
                }
            }
            .frame(height: 80)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Winding Sparkline

    private var windingSparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ω₁/ω₂")
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Canvas { context, size in
                let w = size.width, h = size.height
                let pad: CGFloat = 4
                let values = nights.compactMap(\.windingRatio)
                guard values.count >= 2 else { return }

                let maxVal = max(values.max() ?? 2, 2.0)
                let points: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: pad + CGFloat(i) / CGFloat(values.count - 1) * (w - 2 * pad),
                        y: pad + (1 - v / maxVal) * (h - 2 * pad)
                    )
                }

                var path = Path()
                path.move(to: points[0])
                for pt in points.dropFirst() { path.addLine(to: pt) }
                context.stroke(path, with: .color(.teal), lineWidth: 2)

                for pt in points {
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(.teal))
                }
            }
            .frame(height: 60)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Night List

    private var nightList: some View {
        VStack(spacing: 8) {
            ForEach(nights.reversed()) { night in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(night.date, style: .date)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SpiralColors.text)
                        Text(String(format: loc("neurospiral.history.transitions_fmt"), night.transitionCount))
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", night.stability * 100))
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(night.stability > 0.6 ? SpiralColors.good : .orange)

                    Text("V\(String(format: "%02d", night.dominantVertexIdx))")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build — still expect failure (TrajectoryView, ExportView missing)**

---

### Task 5: Create TrajectoryView

**Files:**
- Create: `spiral journey project/Views/DNA/NeuroSpiralTrajectoryView.swift`

- [ ] **Step 1: Create the animated trajectory view**

```swift
import SwiftUI
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralTrajectoryView: View {
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle
    @State private var visibleCount: Int = 0
    @State private var isPlaying = true
    @State private var speed: Double = 5

    private var pointsPerFrame: Int { max(1, Int(speed)) }

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                Canvas { context, size in
                    drawTorus(context: context, size: size)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: visibleCount) { _, _ in } // force redraw
            }
            .onAppear { advanceAnimation() }

            // Controls
            VStack(spacing: 12) {
                HStack {
                    Button { isPlaying.toggle() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(SpiralColors.accent)
                    }
                    Button {
                        visibleCount = 0
                        isPlaying = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body)
                            .foregroundStyle(SpiralColors.muted)
                    }
                    Spacer()
                    Text("\(visibleCount)/\(analysis.trajectory.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                }

                HStack {
                    Text("1×").font(.caption2).foregroundStyle(SpiralColors.muted)
                    Slider(value: $speed, in: 1...20, step: 1)
                        .tint(SpiralColors.accent)
                    Text("20×").font(.caption2).foregroundStyle(SpiralColors.muted)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.trajectory.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func advanceAnimation() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard isPlaying, visibleCount < analysis.trajectory.count else { continue }
                visibleCount = min(visibleCount + pointsPerFrame, analysis.trajectory.count)
            }
        }
    }

    private func drawTorus(context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let padX: CGFloat = 20, padY: CGFloat = 20
        let plotW = w - 2 * padX, plotH = h - 2 * padY
        let trajectory = analysis.trajectory

        // Grid
        let gridColor = Color.secondary.opacity(0.12)
        for i in 0...4 {
            let x = padX + CGFloat(i) / 4.0 * plotW
            let y = padY + CGFloat(i) / 4.0 * plotH
            context.stroke(Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) }, with: .color(gridColor), lineWidth: 0.5)
            context.stroke(Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) }, with: .color(gridColor), lineWidth: 0.5)
        }

        // Vertices
        for vertex in Tesseract.vertices {
            let (vt, vp) = vertex.torusAngles
            let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
            let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
            let isDominant = vertex.index == analysis.residence.dominantVertex.index
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(isDominant ? .green : .orange.opacity(0.4)))
        }

        guard visibleCount > 0 else { return }

        // Trail: last 30 points with connecting lines
        let trailStart = max(0, visibleCount - 30)
        let trailSlice = trajectory[trailStart..<visibleCount]

        func toScreen(_ point: SIMD4<Double>) -> CGPoint {
            let (theta, phi) = CliffordTorus.angles(of: point)
            return CGPoint(
                x: padX + ((theta + .pi) / (2 * .pi)) * plotW,
                y: padY + ((phi + .pi) / (2 * .pi)) * plotH
            )
        }

        // Historical points (before trail)
        for i in 0..<trailStart {
            let pt = toScreen(trajectory[i])
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)), with: .color(.purple.opacity(0.2)))
        }

        // Trail lines
        let trailArray = Array(trailSlice)
        if trailArray.count >= 2 {
            for i in 1..<trailArray.count {
                let from = toScreen(trailArray[i - 1])
                let to = toScreen(trailArray[i])
                let opacity = Double(i) / Double(trailArray.count)
                var linePath = Path()
                linePath.move(to: from)
                linePath.addLine(to: to)
                context.stroke(linePath, with: .color(.purple.opacity(opacity * 0.8)), lineWidth: 1.5)
            }
        }

        // Current point (head)
        if let last = trailArray.last {
            let pt = toScreen(last)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(.purple))
            context.stroke(Path(ellipseIn: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(.purple.opacity(0.3)), lineWidth: 2)
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build — still expect failure (ExportView missing)**

---

### Task 6: Create ExportView

**Files:**
- Create: `spiral journey project/Views/DNA/NeuroSpiralExportView.swift`

- [ ] **Step 1: Create the export view with CSV generation and ShareLink**

```swift
import SwiftUI
import SpiralKit
import struct SpiralGeometry.WearableSleepSample
import struct SpiralGeometry.WearableTo4DMapper
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralExportView: View {
    let samples: [WearableSleepSample]
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle
    @State private var csvURL: URL?
    @State private var isGenerating = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                summaryCard
                previewCard
                exportButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.export.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { generateCSV() }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.export.summary"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            HStack {
                Label("\(samples.count) epochs", systemImage: "waveform")
                Spacer()
                Label("\(analysis.trajectory.count) points", systemImage: "circle.dotted")
            }
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)

            if let first = samples.first, let last = samples.last {
                HStack {
                    Text(first.timestamp, style: .date)
                    Text("→")
                    Text(last.timestamp, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.export.preview"))
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Text("timestamp,hrv,hr,motion,phase,θ,φ,vertex,code,ω₁,ω₂")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)

            ForEach(0..<min(3, samples.count), id: \.self) { i in
                let row = buildCSVRow(index: i)
                Text(row)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SpiralColors.text.opacity(0.7))
                    .lineLimit(1)
            }

            if samples.count > 3 {
                Text("… \(samples.count - 3) " + loc("neurospiral.export.more_rows"))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Group {
            if let csvURL {
                ShareLink(item: csvURL) {
                    Label(loc("neurospiral.export.share"), systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SpiralColors.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            } else {
                ProgressView()
                    .padding()
            }
        }
    }

    // MARK: - CSV Generation

    private func generateCSV() {
        let mapper = WearableTo4DMapper()
        let header = "timestamp_iso,hrv_ms,heart_rate_bpm,motion_intensity,sleep_phase,theta,phi,vertex_idx,vertex_code,omega1,omega2\n"

        var rows = header
        var prevAngles: (Double, Double)?

        for (i, sample) in samples.enumerated() {
            let point = mapper.map(sample)
            let (theta, phi) = CliffordTorus.angles(of: point)
            let vertex = Tesseract.discretize(point)

            var omega1 = 0.0, omega2 = 0.0
            if let prev = prevAngles {
                omega1 = abs(CliffordTorus.wrapAngle(theta - prev.0))
                omega2 = abs(CliffordTorus.wrapAngle(phi - prev.1))
            }
            prevAngles = (theta, phi)

            let phase: String
            switch sample.sleepStage {
            case .deep: phase = "deep"
            case .rem: phase = "rem"
            case .core: phase = "light"
            case .awake: phase = "awake"
            case .none: phase = "unknown"
            }

            let code = formatCode(vertex.code)
            let ts = ISO8601DateFormatter().string(from: sample.timestamp)
            rows += "\(ts),\(String(format: "%.1f", sample.hrv)),\(String(format: "%.1f", sample.heartRate)),\(String(format: "%.3f", sample.motionIntensity)),\(phase),\(String(format: "%.4f", theta)),\(String(format: "%.4f", phi)),\(vertex.index),\(code),\(String(format: "%.4f", omega1)),\(String(format: "%.4f", omega2))\n"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("neurospiral_export_\(Int(Date().timeIntervalSince1970)).csv")
        try? rows.write(to: fileURL, atomically: true, encoding: .utf8)
        csvURL = fileURL
    }

    private func buildCSVRow(index i: Int) -> String {
        let sample = samples[i]
        let mapper = WearableTo4DMapper()
        let point = mapper.map(sample)
        let (theta, phi) = CliffordTorus.angles(of: point)
        let vertex = Tesseract.discretize(point)
        let ts = ISO8601DateFormatter().string(from: sample.timestamp)
        return "\(ts),\(String(format: "%.1f", sample.hrv)),\(String(format: "%.1f", sample.heartRate)),...,\(vertex.index)"
    }

    private func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))"
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
```

- [ ] **Step 2: Build iOS target**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED (all views now exist)

---

### Task 7: Watch minicard + WatchConnectivity

**Files:**
- Create: `Spiral Watch App Watch App/WatchNeuroSpiralCard.swift`
- Modify: `Spiral Watch App Watch App/ContentView.swift`
- Modify: `Spiral Watch App Watch App/WatchStore.swift`
- Modify: `spiral journey project/Services/WatchConnectivityManager.swift`

- [ ] **Step 1: Add neurospiral fields to WatchStore**

In `WatchStore.swift`, add properties to read neurospiral data from the context. Find the existing stored properties and add:

```swift
    // NeuroSpiral summary (from iPhone analysis)
    var neuroSpiralStability: Double?
    var neuroSpiralDominantIdx: Int?
    var neuroSpiralDominantCode: String?
    var neuroSpiralWinding: Double?
    var neuroSpiralTransitions: Int?
    var neuroSpiralDate: Date?
```

In the `updateFromContext(_ context: [String: Any])` method, add parsing:

```swift
        // NeuroSpiral
        if let nsData = context["neuroSpiralData"] as? [String: Any] {
            neuroSpiralStability = nsData["stability"] as? Double
            neuroSpiralDominantIdx = nsData["dominantIdx"] as? Int
            neuroSpiralDominantCode = nsData["dominantCode"] as? String
            let w = nsData["winding"] as? Double
            neuroSpiralWinding = (w == -1.0) ? nil : w
            neuroSpiralTransitions = nsData["transitions"] as? Int
            if let ts = nsData["date"] as? TimeInterval {
                neuroSpiralDate = Date(timeIntervalSince1970: ts)
            }
        }
```

- [ ] **Step 2: Send neurospiral data in WatchConnectivityManager**

In `WatchConnectivityManager.swift`, find the method that calls `updateApplicationContext` (around line 86). Before that call, add the neurospiral data to the context:

```swift
        // NeuroSpiral data
        if let nsData = UserDefaults(suiteName: "group.xaron.spiral-journey-project")?.dictionary(forKey: "neurospiral-last-night") {
            context["neuroSpiralData"] = [
                "stability": nsData["neurospiral_stability"] ?? 0,
                "dominantIdx": nsData["neurospiral_dominant_idx"] ?? 0,
                "dominantCode": nsData["neurospiral_dominant_code"] ?? "",
                "winding": nsData["neurospiral_winding"] ?? -1.0,
                "transitions": nsData["neurospiral_transitions"] ?? 0,
                "date": nsData["neurospiral_date"] ?? 0,
            ]
        }
```

- [ ] **Step 3: Create WatchNeuroSpiralCard.swift**

```swift
import SwiftUI

struct WatchNeuroSpiralCard: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let stability = store.neuroSpiralStability {
            VStack(spacing: 8) {
                Text("ANOCHE")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchColors.muted)

                Text(String(format: "%.0f%%", stability * 100))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(stability > 0.6 ? WatchColors.good : WatchColors.moderate)

                Text("estabilidad")
                    .font(.system(size: 11))
                    .foregroundStyle(WatchColors.muted)

                if let idx = store.neuroSpiralDominantIdx,
                   let code = store.neuroSpiralDominantCode {
                    Text("V\(String(format: "%02d", idx)) \(code)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(WatchColors.accent)
                }

                if let winding = store.neuroSpiralWinding {
                    Text("ω₁/ω₂ = \(String(format: "%.2f", winding))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WatchColors.muted)
                }

                if let transitions = store.neuroSpiralTransitions {
                    Text("\(transitions) transiciones")
                        .font(.system(size: 10))
                        .foregroundStyle(WatchColors.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.title2)
                    .foregroundStyle(WatchColors.muted)
                Text("NeuroSpiral")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchColors.muted)
                Text("Sin datos")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchColors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 4: Add tab to WatchContentView**

In `ContentView.swift`, add the new tab after `WatchEventLogView`:

```swift
            WatchNeuroSpiralCard()
                .tag(4)
```

- [ ] **Step 5: Build Watch target**

Run: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED

---

### Task 8: Add localization keys

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

- [ ] **Step 1: Add all new neurospiral keys**

Add these keys with 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans):

| Key | EN value |
|-----|----------|
| `neurospiral.hub.stability` | Stability |
| `neurospiral.hub.dominant` | Dominant |
| `neurospiral.hub.history` | History |
| `neurospiral.hub.trajectory` | Trajectory |
| `neurospiral.hub.export` | Export |
| `neurospiral.history.title` | Night History |
| `neurospiral.history.stability_trend` | Stability trend |
| `neurospiral.history.transitions_fmt` | %d transitions |
| `neurospiral.trajectory.title` | Trajectory |
| `neurospiral.export.title` | Export |
| `neurospiral.export.summary` | Export summary |
| `neurospiral.export.preview` | Preview |
| `neurospiral.export.more_rows` | more rows |
| `neurospiral.export.share` | Export CSV |

Follow the exact JSON format used by existing `neurospiral.*` keys. Validate JSON with `python3 -c "import json; json.load(open('...'))"` after editing.

- [ ] **Step 2: Build to verify xcstrings valid**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED

---

### Task 9: Python watch_loader + publish_validate integration

**Files:**
- Create: `/Users/xaron/Desktop/neurospiral/neurospiral/src/data/watch_loader.py`
- Modify: `/Users/xaron/Desktop/neurospiral/neurospiral/scripts/publish_validate.py`

- [ ] **Step 1: Create watch_loader.py**

```python
"""Apple Watch CSV loader for NeuroSpiral pipeline.

Loads CSV exported from Spiral Journey iOS app and returns
data compatible with the EDF-based pipeline.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd


WATCH_LABEL_MAPPING = {
    "deep": "N3",
    "rem": "REM",
    "light": "N2",
    "awake": "W",
    "unknown": "W",
}

STAGE_TO_INT = {"W": 0, "N1": 1, "N2": 2, "N3": 3, "REM": 4}


@dataclass
class WatchRecord:
    """Container for Apple Watch sleep export."""

    subject_id: str
    epochs_4d: np.ndarray        # (N, 4) — raw feature vectors
    labels: np.ndarray           # (N,) — integer stage labels
    label_names: list[str]       # (N,) — string stage names
    torus_angles: np.ndarray     # (N, 2) — (theta, phi)
    vertex_assignments: np.ndarray  # (N,) — vertex indices 0-15
    omega1: np.ndarray           # (N,) — per-epoch angular velocity plane 1
    omega2: np.ndarray           # (N,) — per-epoch angular velocity plane 2
    timestamps: list[datetime] = field(default_factory=list)

    @property
    def n_epochs(self) -> int:
        return len(self.labels)

    @property
    def duration_hours(self) -> float:
        if len(self.timestamps) < 2:
            return 0.0
        return (self.timestamps[-1] - self.timestamps[0]).total_seconds() / 3600


def load_watch_csv(
    csv_path: str | Path,
    subject_id: str | None = None,
) -> WatchRecord:
    """Load CSV exported from Spiral Journey iOS app.

    Parameters
    ----------
    csv_path : path to the exported CSV file
    subject_id : optional subject identifier (defaults to filename stem)

    Returns
    -------
    WatchRecord with pre-computed torus coordinates and vertex assignments.
    """
    csv_path = Path(csv_path)
    if subject_id is None:
        subject_id = csv_path.stem

    df = pd.read_csv(csv_path)

    # Parse timestamps
    timestamps = [datetime.fromisoformat(ts.replace("Z", "+00:00")) for ts in df["timestamp_iso"]]

    # Build 4D feature vectors (matching WearableMapping.swift dimensions)
    epochs_4d = np.column_stack([
        df["hrv_ms"].values,
        df["heart_rate_bpm"].values,
        df["motion_intensity"].values,
        np.array([ts.hour + ts.minute / 60.0 for ts in timestamps]),  # hour of day
    ])

    # Labels
    label_names = [WATCH_LABEL_MAPPING.get(p, "W") for p in df["sleep_phase"]]
    labels = np.array([STAGE_TO_INT[ln] for ln in label_names])

    # Torus coordinates (pre-computed by iOS)
    torus_angles = np.column_stack([df["theta"].values, df["phi"].values])

    # Vertex assignments
    vertex_assignments = df["vertex_idx"].values.astype(int)

    # Angular velocities
    omega1 = df["omega1"].values
    omega2 = df["omega2"].values

    return WatchRecord(
        subject_id=subject_id,
        epochs_4d=epochs_4d,
        labels=labels,
        label_names=label_names,
        torus_angles=torus_angles,
        vertex_assignments=vertex_assignments,
        omega1=omega1,
        omega2=omega2,
        timestamps=timestamps,
    )
```

- [ ] **Step 2: Add --input-type flag to publish_validate.py**

At the top of the `argparse` section in `publish_validate.py`, add:

```python
    parser.add_argument("--input-type", choices=["edf", "watch"], default="edf",
                        help="Input type: 'edf' for Sleep-EDF PSG, 'watch' for iOS CSV export")
    parser.add_argument("--watch-csv", type=str, default=None,
                        help="Path to Apple Watch CSV export (required when --input-type watch)")
```

Add import at the top of the file:

```python
from src.data.watch_loader import load_watch_csv, WatchRecord
```

Add a new function after `process_subject`:

```python
def process_watch_csv(csv_path, subject_id="watch"):
    """Process Apple Watch CSV — torus coords are pre-computed, skip EEG pipeline."""
    record = load_watch_csv(csv_path, subject_id=subject_id)

    rows = []
    for i in range(record.n_epochs):
        row = {
            "stage": record.label_names[i],
            "theta": record.torus_angles[i, 0],
            "phi": record.torus_angles[i, 1],
            "vertex_idx": int(record.vertex_assignments[i]),
            "omega1": float(record.omega1[i]),
            "omega2": float(record.omega2[i]),
        }
        rows.append(row)

    return rows, record.label_names
```

- [ ] **Step 3: Verify Python syntax**

Run: `cd /Users/xaron/Desktop/neurospiral/neurospiral && python3 -c "from src.data.watch_loader import load_watch_csv; print('OK')"`
Expected: OK (or import error for pandas — in which case activate venv first)

---

### Task 10: Final build verification

- [ ] **Step 1: Build iOS**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Build Watch**

Run: `xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS 2>&1 | grep -E "BUILD|error:"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify Python**

Run: `cd /Users/xaron/Desktop/neurospiral/neurospiral && source .venv/bin/activate && python3 -c "from src.data.watch_loader import load_watch_csv; print('watch_loader OK')"`
Expected: watch_loader OK
