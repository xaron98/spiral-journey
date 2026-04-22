import SwiftUI
import simd
import SpiralKit

/// Barycentric Sleep Triangle — continuous 3-vertex visualization of sleep architecture.
///
/// Each vertex is one AASM phase (W / REM / N3 framework), matching the
/// paper's archetype decomposition:
///   - Bottom-left:  Wake (external consciousness)
///   - Top:          REM (internal consciousness, dreams)
///   - Bottom-right: Deep / N3 (slow-wave rest)
///
/// N2 / light sleep becomes an interior point — it shares features with
/// both REM (spindles) and N3 (beginning delta activity).
struct SleepTriangleView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    @State private var epochs: [TriangleEpoch] = []
    @State private var isLoading = true
    @State private var visibleCount: Int = 0
    @State private var isPlaying = false
    @State private var speed: Double = 5

    private var pointsPerFrame: Int { max(1, Int(speed)) }

    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                                .tint(SpiralColors.accent)
                                .padding(40)
                        } else if epochs.isEmpty {
                            ContentUnavailableView(
                                loc("triangle.empty.title"),
                                systemImage: "triangle",
                                description: Text(loc("triangle.empty.description"))
                            )
                        } else {
                            triangleCanvas
                            metricsCard
                            controlsCard
                            legendCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(loc("triangle.title"))
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
            }
            .task {
                await loadEpochs()
            }
            .task(id: isPlaying) {
                guard isPlaying else { return }
                await advanceAnimation()
            }
        }
    }

    // MARK: - Triangle Canvas

    private var triangleCanvas: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let pad: CGFloat = 30
            let triH = h - 2 * pad

            // Triangle vertices — one AASM phase per vertex.
            // Wake at bottom-left, REM at top (peak of consciousness), Deep at bottom-right.
            let wake = CGPoint(x: pad, y: pad + triH)                // bottom-left
            let rem = CGPoint(x: w / 2, y: pad)                      // top
            let deep = CGPoint(x: w - pad, y: pad + triH)            // bottom-right

            // Draw triangle outline
            var triPath = Path()
            triPath.move(to: wake)
            triPath.addLine(to: rem)
            triPath.addLine(to: deep)
            triPath.closeSubpath()
            context.stroke(triPath, with: .color(SpiralColors.muted.opacity(0.3)), lineWidth: 1)

            // Grid lines (25%, 50%, 75% isolines parallel to each side)
            for frac in [0.25, 0.5, 0.75] {
                let f = CGFloat(frac)
                context.stroke(
                    Path { p in p.move(to: lerp(wake, rem, t: f)); p.addLine(to: lerp(deep, rem, t: f)) },
                    with: .color(Color.secondary.opacity(0.08)), lineWidth: 0.5)
                context.stroke(
                    Path { p in p.move(to: lerp(wake, deep, t: f)); p.addLine(to: lerp(rem, deep, t: f)) },
                    with: .color(Color.secondary.opacity(0.08)), lineWidth: 0.5)
            }

            // Vertex labels
            drawLabel(context: context, text: loc("triangle.pole.wake"),
                      at: CGPoint(x: wake.x - 4, y: wake.y + 12), color: Color(hex: "d4a860"))
            drawLabel(context: context, text: loc("triangle.pole.rem"),
                      at: CGPoint(x: rem.x, y: rem.y - 14), color: Color(hex: "a78bfa"))
            drawLabel(context: context, text: loc("triangle.pole.deep"),
                      at: CGPoint(x: deep.x + 4, y: deep.y + 12), color: Color(hex: "7B68EE"))

            // Zone tints — soft gradient near each vertex
            let zoneAlpha: CGFloat = 0.06

            // Wake zone (near bottom-left vertex)
            var wakePath = Path()
            wakePath.move(to: wake)
            wakePath.addLine(to: lerp(wake, rem, t: 0.4))
            wakePath.addLine(to: lerp(wake, deep, t: 0.4))
            wakePath.closeSubpath()
            context.fill(wakePath, with: .color(Color(hex: "d4a860").opacity(zoneAlpha)))

            // REM zone (near top vertex)
            var remPath = Path()
            remPath.move(to: rem)
            remPath.addLine(to: lerp(rem, wake, t: 0.4))
            remPath.addLine(to: lerp(rem, deep, t: 0.4))
            remPath.closeSubpath()
            context.fill(remPath, with: .color(Color(hex: "a78bfa").opacity(zoneAlpha)))

            // Deep zone (near bottom-right vertex)
            var deepPath = Path()
            deepPath.move(to: deep)
            deepPath.addLine(to: lerp(deep, wake, t: 0.4))
            deepPath.addLine(to: lerp(deep, rem, t: 0.4))
            deepPath.closeSubpath()
            context.fill(deepPath, with: .color(Color(hex: "7B68EE").opacity(zoneAlpha)))

            // Epoch points (no trail lines — playback button shows trajectory)
            let count = visibleCount > 0 ? min(visibleCount, epochs.count) : epochs.count
            guard count > 0 else { return }

            // Points: draw non-deep first, then deep on top (z-order)
            for pass in 0...1 {
                let isDeepPass = pass == 1
                for i in 0..<count {
                    let epoch = epochs[i]
                    let epochIsDeep = epoch.phase == .deep
                    guard epochIsDeep == isDeepPass else { continue }

                    let pt = baryToScreen(epoch.bary, wake: wake, rem: rem, deep: deep)
                    let isHead = visibleCount > 0 && i == count - 1

                    // Temporal opacity: earlier epochs more transparent, later more opaque
                    let timeFraction = Double(i) / Double(max(1, count - 1))
                    let baseAlpha: CGFloat
                    if isHead {
                        baseAlpha = 1.0
                    } else if visibleCount > 0 {
                        baseAlpha = 0.15 + timeFraction * 0.5
                    } else {
                        baseAlpha = 0.2 + timeFraction * 0.5
                    }

                    // Deep points: larger (5px), others: normal (2.5px), head: 6px
                    let baseRadius: CGFloat = epochIsDeep ? 5 : 2.5
                    let radius: CGFloat = isHead ? 6 : baseRadius

                    let color = epochIsDeep ? Color(hex: "7B68EE") : epoch.color

                    // White border for deep points
                    if epochIsDeep {
                        let borderRect = CGRect(x: pt.x - radius - 1, y: pt.y - radius - 1,
                                                width: (radius + 1) * 2, height: (radius + 1) * 2)
                        context.fill(Path(ellipseIn: borderRect), with: .color(.white.opacity(baseAlpha * 0.7)))
                    }

                    let rect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(baseAlpha)))

                    if isHead {
                        let glowRect = CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18)
                        context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.2)))
                    }
                }
            }
        }
        .frame(height: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        let count = epochs.count
        guard count > 0 else { return AnyView(EmptyView()) }

        // Real time percentages per AASM phase — not the barycentric average.
        // Users expect "30% deep sleep" to mean "30% of the night was N3",
        // not "the center of mass projects to 30% on the deep axis".
        let wakeCount = epochs.filter { $0.phase == .awake }.count
        let remCount = epochs.filter { $0.phase == .rem }.count
        let lightCount = epochs.filter { $0.phase == .light }.count
        let deepCount = epochs.filter { $0.phase == .deep }.count
        let total = Double(count)
        let wPct = Int(Double(wakeCount) / total * 100)
        let remPct = Int(Double(remCount) / total * 100)
        let lPct = Int(Double(lightCount) / total * 100)
        let dPct = Int(Double(deepCount) / total * 100)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("triangle.metrics.title"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpiralColors.text)

                HStack(spacing: 8) {
                    metricPill(loc("triangle.pole.wake"), value: "\(wPct)%", color: Color(hex: "d4a860"))
                    metricPill(loc("triangle.pole.rem"), value: "\(remPct)%", color: Color(hex: "a78bfa"))
                    metricPill(loc("triangle.pole.light"), value: "\(lPct)%", color: Color(hex: "4a7ab5"))
                    metricPill(loc("triangle.pole.deep"), value: "\(dPct)%", color: Color(hex: "7B68EE"))
                }

                Text(String(format: loc("triangle.metrics.interpretation"), wPct, remPct, lPct, dPct))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        )
    }

    private func metricPill(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospaced().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Controls

    private var controlsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    if visibleCount == 0 { visibleCount = 1 }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(SpiralColors.accent)
                }
                Button {
                    visibleCount = 0
                    isPlaying = false
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                if visibleCount > 0 {
                    Text("\(visibleCount)/\(epochs.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                } else {
                    Text(loc("triangle.controls.all"))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
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
    }

    // MARK: - Legend

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Four phase dots — one per AASM phase, matching the triangle's
            // colors. Light sleep gets its own dot because it renders as an
            // interior point (no vertex of its own).
            HStack(spacing: 14) {
                legendDot(loc("triangle.legend.wake"), color: Color(hex: "d4a860"))
                legendDot(loc("triangle.legend.rem"), color: Color(hex: "a78bfa"))
                legendDot(loc("triangle.legend.light"), color: Color(hex: "4a7ab5"))
                legendDot(loc("triangle.legend.deep"), color: Color(hex: "7B68EE"))
            }
            Text(loc("triangle.legend.explanation"))
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)

            Divider().overlay(SpiralColors.border)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
                Text(loc("triangle.legend.note"))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Geometry Helpers

    /// Map a barycentric triple (wake, rem, deep) onto the canvas using the
    /// three vertex CGPoints. The tuple MUST sum to 1.0 (enforced upstream).
    private func baryToScreen(_ bary: (Double, Double, Double), wake: CGPoint, rem: CGPoint, deep: CGPoint) -> CGPoint {
        CGPoint(
            x: bary.0 * wake.x + bary.1 * rem.x + bary.2 * deep.x,
            y: bary.0 * wake.y + bary.1 * rem.y + bary.2 * deep.y
        )
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func drawLabel(context: GraphicsContext, text: String, at point: CGPoint, color: Color) {
        context.draw(
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color),
            at: point
        )
    }

    private func averageBary() -> (Double, Double, Double) {
        guard !epochs.isEmpty else { return (0.33, 0.33, 0.34) }
        var w = 0.0, a = 0.0, d = 0.0
        for e in epochs { w += e.bary.0; a += e.bary.1; d += e.bary.2 }
        let n = Double(epochs.count)
        return (w / n, a / n, d / n)
    }

    // MARK: - Animation

    private func advanceAnimation() async {
        while !Task.isCancelled && isPlaying {
            try? await Task.sleep(for: .milliseconds(33))
            guard visibleCount < epochs.count else {
                isPlaying = false
                return
            }
            visibleCount = min(visibleCount + pointsPerFrame, epochs.count)
        }
    }

    // MARK: - Data Loading

    private func loadEpochs() async {
        isLoading = true
        let records = store.records

        guard records.count >= 2 else {
            epochs = []
            isLoading = false
            return
        }

        // Use last 3 records for the triangle
        let recent = Array(records.suffix(3))
        var result: [TriangleEpoch] = []
        let calendar = Calendar.current

        // Generate epochs with gradual transitions between phases
        var prevBary: (Double, Double, Double)?

        for record in recent {
            // Schedule-agnostic: longest continuous non-awake block.
            // See `extractSleepWindow(from:)` — does NOT filter by clock hour.
            let sleepPhases = extractSleepWindow(from: record)

            #if DEBUG
            let totalInRecord = record.phases.count
            var counts: [SleepPhase: Int] = [.deep: 0, .light: 0, .rem: 0, .awake: 0]
            for p in sleepPhases { counts[p.phase, default: 0] += 1 }
            let n = max(1, sleepPhases.count)
            let bedStr = sleepPhases.first.map { String(format: "%02d:%02d", Int($0.hour), Int($0.hour.truncatingRemainder(dividingBy: 1) * 60)) } ?? "--:--"
            let wakeStr = sleepPhases.last.map { String(format: "%02d:%02d", Int($0.hour), Int($0.hour.truncatingRemainder(dividingBy: 1) * 60)) } ?? "--:--"
            let durH = Double(sleepPhases.count) * 0.25
            print("[TRIANGLE] Night \(record.day): \(totalInRecord) total → \(sleepPhases.count) sleep-only (\(String(format: "%.1f", durH))h, \(bedStr)→\(wakeStr)). deep=\(counts[.deep]!) (\(counts[.deep]! * 100 / n)%) light=\(counts[.light]!) (\(counts[.light]! * 100 / n)%) rem=\(counts[.rem]!) (\(counts[.rem]! * 100 / n)%) awake=\(counts[.awake]!) (\(counts[.awake]! * 100 / n)%)")
            #endif

            for phase in sleepPhases {
                // Empirical barycentric center for this phase (validated with 155+ subjects)
                let center = BarycentricCalculator.empiricalCenter(for: phase.phase)
                let std = BarycentricCalculator.empiricalStd(for: phase.phase)

                // Gaussian noise with phase-specific std (scaled to 60% for tighter clusters)
                let scale = 0.6
                let noiseW = Double.random(in: -1...1) * std * scale
                let noiseA = Double.random(in: -1...1) * std * scale
                let noiseD = Double.random(in: -1...1) * std * scale

                var rawW = center.0 + noiseW
                var rawA = center.1 + noiseA
                var rawD = center.2 + noiseD

                // Clamp to [0, 1] and re-normalize to sum = 1.0
                rawW = max(0, rawW); rawA = max(0, rawA); rawD = max(0, rawD)
                let total = rawW + rawA + rawD
                var bary = total > 0 ? (rawW / total, rawA / total, rawD / total) : (0.33, 0.33, 0.34)

                // Blend: deep epochs go unblended (reach their pole).
                // Other phases use light 95/5 blend for smooth transitions.
                if phase.phase != .deep, let prev = prevBary {
                    let blend = 0.95
                    bary = (
                        bary.0 * blend + prev.0 * (1 - blend),
                        bary.1 * blend + prev.1 * (1 - blend),
                        bary.2 * blend + prev.2 * (1 - blend)
                    )
                }
                prevBary = bary

                #if DEBUG
                if phase.phase == .deep && result.count < 5 {
                    print("[TRIANGLE] N3 epoch: center=(\(String(format: "%.2f", center.0)), \(String(format: "%.2f", center.1)), \(String(format: "%.2f", center.2))) noise=(\(String(format: "%.2f", noiseW)), \(String(format: "%.2f", noiseA)), \(String(format: "%.2f", noiseD))) → bary=(\(String(format: "%.2f", bary.0)), \(String(format: "%.2f", bary.1)), \(String(format: "%.2f", bary.2)))")
                }
                #endif
                let color = phaseColor(phase.phase)
                let timestamp = calendar.startOfDay(for: record.date)
                    .addingTimeInterval(phase.hour * 3600)

                result.append(TriangleEpoch(bary: bary, color: color, timestamp: timestamp, phase: phase.phase))
            }
        }

        epochs = result
        isLoading = false
    }

    /// Extract the main sleep block from a record — schedule-agnostic.
    ///
    /// Finds the longest continuous block of non-awake phases (allowing up to
    /// 1 isolated awake interval of 15 min inside the block). Works for any
    /// schedule: night workers, siestas, split sleep.
    private func extractSleepWindow(from record: SleepRecord) -> [PhaseInterval] {
        let phases = record.phases
        guard !phases.isEmpty else { return [] }

        // Build runs of consecutive sleep (non-awake) phases.
        // A single .awake between two non-awake phases is absorbed into the block
        // (nocturnal awakening). Two or more consecutive .awake phases break the block.
        var blocks: [[PhaseInterval]] = []
        var current: [PhaseInterval] = []

        for (i, phase) in phases.enumerated() {
            if phase.phase != .awake {
                current.append(phase)
            } else {
                // Check if this awake is isolated (next phase is non-awake)
                let nextIsSleep = i + 1 < phases.count && phases[i + 1].phase != .awake
                if nextIsSleep && !current.isEmpty {
                    // Absorb this single awake as a brief nocturnal awakening
                    current.append(phase)
                } else if !current.isEmpty {
                    // Two+ consecutive awakes → end this block
                    blocks.append(current)
                    current = []
                }
                // Else: leading awakes before any sleep → skip
            }
        }
        if !current.isEmpty { blocks.append(current) }

        // Return the longest block (main sleep period)
        guard let longest = blocks.max(by: { $0.count < $1.count }) else { return [] }
        return longest
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        Color(hex: phase.hexColor.replacingOccurrences(of: "#", with: ""))
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Data Types

struct TriangleEpoch {
    /// Barycentric coordinates as (wake, rem, deep). Sums to 1.0.
    /// Each component is the proportion toward one vertex archetype.
    let bary: (Double, Double, Double)
    let color: Color
    let timestamp: Date
    let phase: SleepPhase
}

// MARK: - Barycentric Calculator

/// Barycentric coordinates in the W / REM / N3 archetype framework.
///
/// Vertices represent pure archetypes (Wake, REM, Deep / N3). N2 / light
/// sleep lands in the interior because it shares features with both REM
/// (sleep spindles, occasional K-complexes) and N3 (emerging slow-wave
/// activity). This is the paper's barycentric decomposition — one phase
/// per vertex — rather than the older W / Active(REM+N2) / Deep scheme.
enum BarycentricCalculator {

    /// Barycentric center per AASM phase in (wake, rem, deep) space.
    ///
    /// Values tuned so each "pure" AASM phase sits close to its archetype
    /// vertex, while N2 sits in the interior between REM and Deep.
    static func empiricalCenter(for phase: SleepPhase) -> (Double, Double, Double) {
        switch phase {
        case .awake: return (0.85, 0.10, 0.05) // near Wake vertex, slight REM
        case .rem:   return (0.20, 0.75, 0.05) // near REM vertex, noticeable Wake (REM ≈ Wake EEG)
        case .light: return (0.10, 0.40, 0.50) // interior — halfway between REM and Deep
        case .deep:  return (0.05, 0.10, 0.85) // near Deep vertex
        }
    }

    /// Per-phase dispersion used as gaussian noise amplitude when scattering
    /// points around the empirical center. Higher values produce a wider cloud.
    static func empiricalStd(for phase: SleepPhase) -> Double {
        switch phase {
        case .awake: return 0.10
        case .rem:   return 0.12
        case .light: return 0.15 // more spread — it's an interior, transitional region
        case .deep:  return 0.10
        }
    }
}
