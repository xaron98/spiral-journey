import SwiftUI
import SpiralKit

/// 3D helix view of the sleep spiral.
/// The helix axis is vertical — time winds upward.
/// Pinch gesture controls elevation (logarithmic zoom):
///   - Pinch out → look from above (flat, like the 2D view)
///   - Pinch in  → look from the side (full 3D helix depth)
/// When `externalElevation` / `externalAzimuth` bindings are provided,
/// the view uses those values instead of its own state (used by WeekComparisonCard).
struct Spiral3DView: View {

    let records: [SleepRecord]
    let episodes: [SleepEpisode]
    let spiralType: SpiralType
    let period: Double
    let maxReachedTurns: Double

    /// Optional external bindings for synchronized control
    var externalElevation: Binding<Double>? = nil
    var externalAzimuth: Binding<Double>? = nil

    // Elevation angle in radians: 0 = side-on, π/2 = top-down (2D)
    @State private var elevation: Double = 0.55       // start ~31° from side
    @State private var baseElevation: Double = 0.55
    @GestureState private var pinchScale: CGFloat = 1.0

    private var currentElevation: Double {
        externalElevation?.wrappedValue ?? clampElevation(elevation * Double(pinchScale))
    }
    private var currentAzimuth: Double {
        externalAzimuth?.wrappedValue ?? 0.0
    }

    var body: some View {
        Canvas { context, size in
            drawHelix(context: context, size: size,
                      elevation: currentElevation,
                      azimuth: currentAzimuth)
        }
        .background(SpiralColors.bg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .gesture(
            MagnifyGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    elevation = clampElevation(elevation * Double(value.magnification))
                    baseElevation = elevation
                }
        )
    }

    // MARK: - Elevation clamp

    private func clampElevation(_ e: Double) -> Double {
        // Log scale: map [0.05 … π/2] range
        max(0.05, min(.pi / 2, e))
    }

    // MARK: - 3D projection

    /// Project a 3D point (x, y, z) to 2D canvas using perspective.
    /// Camera is at elevation `elev` above the XZ plane, rotated by `azimuth` around Y axis.
    private func project(_ x: Double, _ y: Double, _ z: Double,
                         cx: Double, cy: Double,
                         fov: Double, elevation elev: Double, azimuth az: Double) -> CGPoint {
        // Rotate around Y axis by azimuth (horizontal spin)
        let cosA = cos(az)
        let sinA = sin(az)
        let rx = x * cosA + z * sinA
        let rz0 = -x * sinA + z * cosA

        // Rotate around X axis by elevation
        let cosE = cos(elev)
        let sinE = sin(elev)
        let ry = y * cosE - rz0 * sinE
        let rz = y * sinE + rz0 * cosE

        // Perspective divide
        let camDist = fov
        let scale = camDist / (camDist + rz)
        return CGPoint(x: cx + rx * scale, y: cy - ry * scale)
    }

    // MARK: - Drawing

    private func drawHelix(context: GraphicsContext, size: CGSize, elevation: Double, azimuth: Double = 0.0) {
        let cx = size.width / 2
        let cy = size.height / 2
        let fov = size.height * 1.5   // perspective distance

        let turns = max(maxReachedTurns, 1.0)
        let scaleDays = max(1, Int(ceil(turns)))

        // Helix parameters — radius based on width, height spans the full canvas height
        let helixRadius = size.width * 0.30
        let helixHeight = size.height * 0.85   // total vertical span
        let turnsTotal = turns

        // Draw guide rings (faint circles at each day boundary)
        for day in 0...scaleDays {
            let t = Double(day)
            let frac = t / turnsTotal
            let z = (frac - 0.5) * helixHeight   // center vertically
            var ringPath = Path()
            let steps = 60
            for i in 0...steps {
                let angle = Double(i) / Double(steps) * 2 * .pi - .pi / 2
                let px = helixRadius * cos(angle)
                let py = helixRadius * sin(angle)
                let pt = project(px, 0, py + z, cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth)
                if i == 0 { ringPath.move(to: pt) } else { ringPath.addLine(to: pt) }
            }
            ringPath.closeSubpath()
            let isWeek = day % 7 == 0
            context.stroke(ringPath,
                           with: .color(SpiralColors.border.opacity(isWeek ? 0.45 : 0.2)),
                           lineWidth: isWeek ? 0.8 : 0.4)
        }

        // Draw vertical axis lines
        let axisSteps = 8
        for i in 0..<axisSteps {
            let angle = Double(i) / Double(axisSteps) * 2 * .pi - .pi / 2
            let px = helixRadius * cos(angle)
            let py = helixRadius * sin(angle)
            let top = project(px, 0, py + helixHeight * 0.5, cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth)
            let bot = project(px, 0, py - helixHeight * 0.5, cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth)
            var p = Path()
            p.move(to: bot); p.addLine(to: top)
            context.stroke(p, with: .color(SpiralColors.border.opacity(0.15)), lineWidth: 0.4)
        }

        // Draw backbone helix
        let pathSteps = Int(turns * 120)
        var backbone = Path()
        for i in 0...pathSteps {
            let t = Double(i) / Double(pathSteps) * turns
            let angle = t * 2 * .pi - .pi / 2
            let frac = t / turnsTotal
            let z = (frac - 0.5) * helixHeight
            let px = helixRadius * cos(angle)
            let py = helixRadius * sin(angle)
            let pt = project(px, 0, py + z, cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth)
            if i == 0 { backbone.move(to: pt) } else { backbone.addLine(to: pt) }
        }
        // Triple-layer Liquid Glass backbone:
        // 1. Translucent wide base (refraction glow)
        context.stroke(backbone,
                       with: .color(Color(hex: "3a4055").opacity(0.5)),
                       style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        // 2. Core stroke (slightly translucent body)
        context.stroke(backbone,
                       with: .color(Color(hex: "5a6a85").opacity(0.7)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        // 3. Specular highlight (thin white top edge)
        context.stroke(backbone,
                       with: .color(Color.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // Draw sleep/wake colored overlay
        drawPhaseOverlay(context: context, size: size, cx: cx, cy: cy,
                         fov: fov, elevation: elevation, azimuth: azimuth,
                         helixRadius: helixRadius, helixHeight: helixHeight,
                         turnsTotal: turnsTotal)
    }

    private func drawPhaseOverlay(context: GraphicsContext, size: CGSize,
                                  cx: Double, cy: Double, fov: Double, elevation: Double, azimuth: Double,
                                  helixRadius: Double, helixHeight: Double, turnsTotal: Double) {
        for record in records {
            let phases = record.phases
            guard !phases.isEmpty else { continue }

            var runPhase = phases[0].phase
            var path = Path()
            var started = false

            func commitRun() {
                guard started else { return }
                let color = phaseColor3D(runPhase)
                let isSleep = runPhase != .awake
                let lw: Double = isSleep ? 5.0 : 4.0
                // Triple-layer Liquid Glass:
                // 1. Wide translucent glow (refraction)
                context.stroke(path,
                               with: .color(color.opacity(0.2)),
                               style: StrokeStyle(lineWidth: lw + 6, lineCap: .round, lineJoin: .round))
                // 2. Core stroke (glass body)
                context.stroke(path,
                               with: .color(color.opacity(isSleep ? 0.7 : 0.5)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                // 3. Specular highlight (top edge for sleep only)
                if isSleep {
                    context.stroke(path,
                                   with: .color(Color.white.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
                }
                path = Path()
                started = false
            }

            for (i, phase) in phases.enumerated() {
                if phase.phase != runPhase {
                    let pt = helixPoint(day: record.day, hour: phase.hour,
                                        cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth,
                                        helixRadius: helixRadius, helixHeight: helixHeight,
                                        turnsTotal: turnsTotal)
                    path.addLine(to: pt)
                    commitRun()
                    runPhase = phase.phase
                }
                let pt = helixPoint(day: record.day, hour: phase.hour,
                                    cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth,
                                    helixRadius: helixRadius, helixHeight: helixHeight,
                                    turnsTotal: turnsTotal)
                if !started { path.move(to: pt); started = true }
                else { path.addLine(to: pt) }
                if i == phases.count - 1 {
                    let ptEnd = helixPoint(day: record.day, hour: period,
                                           cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth,
                                           helixRadius: helixRadius, helixHeight: helixHeight,
                                           turnsTotal: turnsTotal)
                    path.addLine(to: ptEnd)
                    commitRun()
                }
            }
        }
    }

    private func helixPoint(day: Int, hour: Double,
                             cx: Double, cy: Double, fov: Double, elevation: Double, azimuth: Double,
                             helixRadius: Double, helixHeight: Double,
                             turnsTotal: Double) -> CGPoint {
        let t = Double(day) + hour / period
        let angle = t * 2 * .pi - .pi / 2
        let frac = t / turnsTotal
        let z = (frac - 0.5) * helixHeight
        let px = helixRadius * cos(angle)
        let py = helixRadius * sin(angle)
        return project(px, 0, py + z, cx: cx, cy: cy, fov: fov, elevation: elevation, azimuth: azimuth)
    }

    private func phaseColor3D(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "3a7bd5")
        case .rem:   return Color(hex: "a855f7")
        case .light: return Color(hex: "60a5fa")
        case .awake: return Color(hex: "f5c842")
        }
    }
}
