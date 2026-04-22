import SwiftUI
import SpiralKit
import struct SpiralGeometry.WearableSleepSample
import struct SpiralGeometry.WearableTo4DMapper
import struct SpiralGeometry.SleepTrajectoryAnalysis
import struct SpiralGeometry.TesseractVertex
import struct SpiralGeometry.VertexResidence
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus
import enum SpiralGeometry.SleepStage

/// NeuroSpiral 4D — maps sleep trajectory onto a Clifford torus
/// with 16 tesseract micro-states.
struct NeuroSpiralView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    @State private var analysis: SleepTrajectoryAnalysis?
    @State private var isLoading = true
    @State private var showingInfo = false
    @State private var perNightAnalyses: [NightAnalysis] = []
    @State private var retainedSamples: [WearableSleepSample] = []

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
                            actionButtonsRow(analysis)
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
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
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

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text(loc("neurospiral.header.title"))
                    .font(.headline)
                    .foregroundStyle(SpiralColors.text)
                Spacer()
            }
            Text(loc("neurospiral.header.subtitle"))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Loading / Empty

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SpiralColors.accent)
            Text(loc("neurospiral.loading"))
                .font(.subheadline)
                .foregroundStyle(SpiralColors.muted)
        }
        .padding(40)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            loc("neurospiral.empty.title"),
            systemImage: "moon.zzz",
            description: Text(loc("neurospiral.empty.description"))
        )
    }

    // MARK: - Hero Metrics Row

    private func heroMetricsRow(_ analysis: SleepTrajectoryAnalysis) -> some View {
        HStack(spacing: 12) {
            heroMetric(
                value: String(format: "%.0f%%", analysis.residence.stabilityScore * 100),
                label: loc("neurospiral.stability"),
                color: analysis.residence.stabilityScore > 0.6 ? SpiralColors.good : .orange
            )
            heroMetric(
                value: "V\(String(format: "%02d", analysis.residence.dominantVertex.index))",
                label: loc("neurospiral.dominant.short"),
                color: .purple
            )
            heroMetric(
                value: analysis.windingRatio.map { String(format: "%.2f", $0) } ?? "---",
                label: "w\u{2081}/w\u{2082}",
                color: .orange
            )
        }
    }

    private func heroMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mini Torus Card

    private func miniTorusCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        NavigationLink {
            NeuroSpiralTorusDetailView(analysis: analysis)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(loc("neurospiral.torus.title"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }

                torusCanvas(analysis, height: 200)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func torusCanvas(_ analysis: SleepTrajectoryAnalysis, height: CGFloat) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let padX: CGFloat = 16
            let padY: CGFloat = 16

            // Grid: 4x4 tesseract cells
            let gridColor = Color.secondary.opacity(0.12)
            for i in 0...4 {
                let xFrac = CGFloat(i) / 4.0
                let yFrac = CGFloat(i) / 4.0
                let x = padX + xFrac * (w - 2 * padX)
                let y = padY + yFrac * (h - 2 * padY)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) },
                    with: .color(gridColor), lineWidth: 0.5
                )
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) },
                    with: .color(gridColor), lineWidth: 0.5
                )
            }

            // Trajectory points
            let plotW = w - 2 * padX
            let plotH = h - 2 * padY
            for point in analysis.trajectory {
                let (theta, phi) = CliffordTorus.angles(of: point)
                let x = padX + ((theta + .pi) / (2 * .pi)) * plotW
                let y = padY + ((phi + .pi) / (2 * .pi)) * plotH
                let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: rect), with: .color(.purple.opacity(0.45)))
            }

            // Tesseract vertices
            for vertex in Tesseract.vertices {
                let (vt, vp) = vertex.torusAngles
                let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
                let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                let isDominant = vertex.index == analysis.residence.dominantVertex.index
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isDominant ? .green : .orange.opacity(0.5))
                )
            }
        }
        .frame(height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons Row

    private func actionButtonsRow(_ analysis: SleepTrajectoryAnalysis) -> some View {
        HStack(spacing: 12) {
            actionButton(
                icon: "calendar.badge.clock",
                label: loc("neurospiral.action.history"),
                destination: NeuroSpiralHistoryView(nights: perNightAnalyses)
            )
            actionButton(
                icon: "point.3.connected.trianglepath.dotted",
                label: loc("neurospiral.action.trajectory"),
                destination: NeuroSpiralTrajectoryView(analysis: analysis)
            )
            actionButton(
                icon: "square.and.arrow.up",
                label: loc("neurospiral.action.export"),
                destination: NeuroSpiralExportView(samples: retainedSamples, analysis: analysis)
            )
        }
    }

    private func actionButton<D: View>(icon: String, label: String, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(SpiralColors.accent)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Dominant Card

    private func compactDominantCard(_ analysis: SleepTrajectoryAnalysis) -> some View {
        let vertex = analysis.residence.dominantVertex
        let code = vertex.code

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("neurospiral.dominant.title"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text("V\(String(format: "%02d", vertex.index))")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(SpiralColors.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.2), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                dimensionRow(loc("neurospiral.dim.autonomic"), value: code.x,
                             positive: loc("neurospiral.dim.high"), negative: loc("neurospiral.dim.low"))
                dimensionRow(loc("neurospiral.dim.stillness"), value: code.y,
                             positive: loc("neurospiral.dim.quiet"), negative: loc("neurospiral.dim.movement"))
                dimensionRow(loc("neurospiral.dim.cardiac"), value: code.z,
                             positive: loc("neurospiral.dim.slow"), negative: loc("neurospiral.dim.fast"))
                dimensionRow(loc("neurospiral.dim.circadian"), value: code.w,
                             positive: loc("neurospiral.dim.diurnal"), negative: loc("neurospiral.dim.nocturnal"))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Sheet

    private var neuroSpiralInfoView: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // 1. Intuitive intro
                    infoSection(
                        icon: "moon.stars.fill", iconColor: .purple,
                        title: loc("neurospiral.info.analogy.title"),
                        body: loc("neurospiral.info.analogy.body")
                    )

                    // 2. Two-process model
                    infoSection(
                        icon: "wave.3.right", iconColor: .teal,
                        title: loc("neurospiral.info.twoprocess.title"),
                        body: loc("neurospiral.info.twoprocess.body")
                    )

                    // 3. Why a torus
                    infoSection(
                        icon: "circle.circle", iconColor: .orange,
                        title: loc("neurospiral.info.torus.title"),
                        body: loc("neurospiral.info.torus.body")
                    )

                    // 4. The 4 dimensions
                    infoSection(
                        icon: "cube.transparent", iconColor: .indigo,
                        title: loc("neurospiral.info.dimensions.title"),
                        body: loc("neurospiral.info.dimensions.body")
                    )

                    // 5. The 16 micro-states
                    infoSection(
                        icon: "square.grid.4x3.fill", iconColor: .mint,
                        title: loc("neurospiral.info.microstates.title"),
                        body: loc("neurospiral.info.microstates.body")
                    )

                    // 6. Reading the chart
                    infoSection(
                        icon: "chart.dots.scatter", iconColor: .purple,
                        title: loc("neurospiral.info.reading.title"),
                        body: loc("neurospiral.info.reading.body")
                    )

                    // 7. Oscillators ω₁ / ω₂
                    infoSection(
                        icon: "waveform.path.ecg", iconColor: .red,
                        title: loc("neurospiral.info.oscillators.title"),
                        body: loc("neurospiral.info.oscillators.body")
                    )

                    // 8. Transitions
                    infoSection(
                        icon: "arrow.triangle.swap", iconColor: .yellow,
                        title: loc("neurospiral.info.transitions_detail.title"),
                        body: loc("neurospiral.info.transitions_detail.body")
                    )

                    // 9. Stability
                    infoSection(
                        icon: "waveform.path", iconColor: .green,
                        title: loc("neurospiral.info.stability.title"),
                        body: loc("neurospiral.info.stability.body")
                    )

                    // 10. Practical meaning
                    infoSection(
                        icon: "lightbulb.fill", iconColor: .orange,
                        title: loc("neurospiral.info.practical.title"),
                        body: loc("neurospiral.info.practical.body")
                    )

                    // 11. Data source & methodology
                    infoSection(
                        icon: "applewatch", iconColor: .teal,
                        title: loc("neurospiral.info.datasource.title"),
                        body: loc("neurospiral.info.datasource.body")
                    )

                    // 12. Limitations
                    infoSection(
                        icon: "exclamationmark.triangle", iconColor: SpiralColors.muted,
                        title: loc("neurospiral.info.limits.title"),
                        body: loc("neurospiral.info.limits.body")
                    )

                    Divider()

                    Text(loc("neurospiral.info.reference"))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("neurospiral.info.nav"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showingInfo = false }
                }
            }
        }
    }

    private func infoSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SpiralColors.text)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(SpiralColors.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func dimensionRow(_ label: String, value: Int, positive: String, negative: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
            Text(value > 0 ? positive : negative)
                .font(.caption2.weight(.medium))
                .foregroundStyle(value > 0 ? SpiralColors.good : .orange)
            Image(systemName: value > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(value > 0 ? SpiralColors.good : .orange)
        }
    }

    private func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "[\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))]"
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Data Loading

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
        let nights = buildPerNightAnalyses(records: records, hrvData: hrvData, mapper: mapper)

        if let encoded = try? JSONEncoder().encode(mapper.baseline) {
            defaults?.set(encoded, forKey: "neurospiral-baseline")
        }

        writeWatchData(analysis: result, defaults: defaults)

        analysis = result
        perNightAnalyses = nights
        retainedSamples = allSamples
        isLoading = false
    }

    /// Build WearableSleepSample from SleepRecord phases + NightlyHRV.
    ///
    /// Uses a physiological random walk driven by the real phase sequence.
    /// Within each phase, features drift smoothly (90% previous + 10% target + noise).
    /// Transitions between phases interpolate over 3-4 epochs for continuity.
    private func buildSamplesFromRecords(
        _ records: [SleepRecord],
        hrvData: [NightlyHRV]
    ) -> [WearableSleepSample] {
        let recentRecords = records.suffix(7)
        let calendar = Calendar.current
        let isoFmt = ISO8601DateFormatter()
        var samples: [WearableSleepSample] = []

        var hrvByDate: [String: Double] = [:]
        for hrv in hrvData {
            hrvByDate[isoFmt.string(from: calendar.startOfDay(for: hrv.date))] = hrv.meanSDNN
        }

        // Phase-specific targets: (hrvMod, hrMod, motionMod)
        let phaseTargets: [SleepPhase: (Double, Double, Double)] = [
            .deep:  (1.40, 0.82, 0.008),  // strongest HRV, slowest HR, stillest
            .light: (1.15, 0.90, 0.020),   // moderate
            .rem:   (0.85, 0.97, 0.035),   // lower HRV, slightly faster HR
            .awake: (0.65, 1.12, 0.18),    // lowest HRV, fastest HR, most motion
        ]

        // Phase-specific dispersions (std of the random walk noise)
        let phaseStd: [SleepPhase: Double] = [
            .awake: 0.147, .light: 0.192, .deep: 0.152, .rem: 0.185
        ]

        for record in recentRecords {
            let nightHRV = hrvByDate[isoFmt.string(from: calendar.startOfDay(for: record.date))] ?? 50.0

            // Running state for the random walk
            var currentHRV = nightHRV * 0.65   // start near Wake
            var currentHR  = 65.0 * 1.12
            var currentMotion = 0.18
            var prevPhase: SleepPhase? = nil
            var transitionProgress = 0  // counts epochs during a transition

            for phase in record.phases {
                let target = phaseTargets[phase.phase] ?? (1.0, 1.0, 0.05)
                let std = phaseStd[phase.phase] ?? 0.15
                let sleepStage = mapPhase(phase.phase)

                // Detect phase transition
                let isTransition = prevPhase != nil && prevPhase != phase.phase
                if isTransition { transitionProgress = 0 }
                let transitionEpochs = 4  // interpolate over 4 epochs

                // Generate 30 epochs of 30s within this 15-min interval
                for epoch in 0..<30 {
                    let secondsOffset = phase.hour * 3600 + Double(epoch) * 30
                    let timestamp = calendar.startOfDay(for: record.date)
                        .addingTimeInterval(secondsOffset)

                    // Target values for this phase
                    let targetHRV = nightHRV * target.0
                    let targetHR  = 65.0 * target.1
                    let targetMotion = target.2

                    // Random walk: 90% previous + 10% target + gaussian noise
                    let drift = 0.10  // attraction toward target
                    let momentum = 0.90  // carry-over from previous epoch

                    // Gaussian-ish noise (Box-Muller approximation via uniform sum)
                    let noise = (Double.random(in: -1...1) + Double.random(in: -1...1)) / 2.0 * std

                    // Transition interpolation: during first 4 epochs of a new phase,
                    // blend more strongly toward target
                    let transitionBlend: Double
                    if transitionProgress < transitionEpochs {
                        transitionBlend = Double(transitionProgress + 1) / Double(transitionEpochs)
                        transitionProgress += 1
                    } else {
                        transitionBlend = 1.0
                    }

                    let effectiveDrift = drift + (1.0 - transitionBlend) * 0.3  // stronger pull during transition

                    currentHRV = currentHRV * (1.0 - effectiveDrift) + targetHRV * effectiveDrift + noise * nightHRV * 0.1
                    currentHR  = currentHR  * (1.0 - effectiveDrift) + targetHR  * effectiveDrift + noise * 5.0
                    currentMotion = currentMotion * (1.0 - effectiveDrift) + targetMotion * effectiveDrift + abs(noise) * 0.03

                    // Clamp to physiological ranges
                    let hrv = max(5, min(120, currentHRV))
                    let hr  = max(40, min(100, currentHR))
                    let motion = max(0, min(1.0, currentMotion))

                    samples.append(WearableSleepSample(
                        hrv: hrv,
                        heartRate: hr,
                        motionIntensity: motion,
                        sleepStage: sleepStage,
                        timestamp: timestamp
                    ))
                }
                prevPhase = phase.phase
            }
        }

        return samples
    }

    /// Map SpiralKit SleepPhase → Natural SleepStage (3 states, not 5).
    private func mapPhase(_ phase: SleepPhase) -> SleepStage {
        switch phase {
        case .deep:  return .nrem   // Deep pole (depth 0.7-1.0)
        case .light: return .nrem   // Deep pole (depth 0.3-0.6)
        case .rem:   return .rem    // Active pole, muscles disconnected
        case .awake: return .active // Active pole
        }
    }

    /// Phase-dependent modulation factors for (HRV, HR, motion).
    /// Uses the natural 3-state model: active (W+N1), nrem (continuous depth), rem.
    private func phaseModulation(_ stage: SleepStage) -> (Double, Double, Double) {
        switch stage {
        case .nrem:   return (1.25, 0.87, 0.015)  // Elevated HRV, low HR, minimal motion
        case .rem:    return (0.9, 0.95, 0.03)     // Moderate HRV, slight HR increase
        case .active: return (0.7, 1.10, 0.15)     // Low HRV, higher HR, motion
        }
    }

    private func hrvStandardDeviation(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard n > 1 else { return 20.0 }
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        return max(sqrt(variance), 1.0)
    }

    // MARK: - Per-Night Analysis

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
        // Delegate to the main builder with a single-record array
        return buildSamplesFromRecords([record], hrvData: hrvData)
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
}

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
