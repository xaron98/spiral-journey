import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Large 240pt dial for the Plan screen. Draws full 24-hour clock with
/// ticks, a glowing purple arc for the optimal window, and a pointer
/// dot at the target hour.
///
/// When `targetHour` is a binding, the dial becomes interactive: drag
/// the pointer around the clock face to scrub the target bedtime. The
/// optimal window arc follows the target (±15 min window).
struct CoachTargetDialView: View {
    var size: CGFloat = 240
    @Binding var targetHour: Double
    var windowHalfWidth: Double = 0.25     // hours (±15 min by default)
    var color: Color = CoachTokens.purple
    var snapMinutes: Int = 5               // drag snaps to nearest N minutes

    @State private var isDragging = false

    // Read-only initializer for callers that don't need interaction.
    init(size: CGFloat = 240,
         targetHour: Binding<Double>,
         windowHalfWidth: Double = 0.25,
         color: Color = CoachTokens.purple,
         snapMinutes: Int = 5) {
        self.size = size
        self._targetHour = targetHour
        self.windowHalfWidth = windowHalfWidth
        self.color = color
        self.snapMinutes = snapMinutes
    }

    var body: some View {
        Canvas { ctx, _ in
            let r: CGFloat = 100
            let c = CGPoint(x: size / 2, y: size / 2)

            // Soft radial glow behind.
            let glowRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: glowRect),
                     with: .radialGradient(
                        Gradient(colors: [.clear, color.opacity(0.2)]),
                        center: c, startRadius: r * 0.6, endRadius: r))

            // Outer hairline.
            ctx.stroke(Path(ellipseIn: glowRect),
                       with: .color(Color.white.opacity(0.06)), lineWidth: 1)

            // Track.
            let trackRect = glowRect.insetBy(dx: 4, dy: 4)
            ctx.stroke(Path(ellipseIn: trackRect),
                       with: .color(Color.white.opacity(0.08)), lineWidth: 6)

            // Optimal window arc (centered on targetHour).
            let toRad = { (h: Double) -> Double in (h / 24.0) * 2 * .pi - .pi / 2 }
            let windowStart = targetHour - windowHalfWidth
            let windowEnd   = targetHour + windowHalfWidth
            var arc = Path()
            arc.addArc(center: c, radius: r - 4,
                       startAngle: .radians(toRad(windowStart)),
                       endAngle: .radians(toRad(windowEnd)),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))

            // Hour ticks.
            for h in 0..<24 {
                let a = toRad(Double(h))
                let isMajor = h % 6 == 0
                let r1 = r - 4
                let r2 = isMajor ? r - 14 : r - 10
                let p1 = CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a))
                let p2 = CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a))
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                ctx.stroke(tick,
                           with: .color(isMajor ? Color.white.opacity(0.5) : Color.white.opacity(0.15)),
                           lineWidth: isMajor ? 1.5 : 1)
            }

            // Labels 00 / 06 / 12 / 18.
            for (h, label) in [(0, "00"), (6, "06"), (12, "12"), (18, "18")] {
                let a = toRad(Double(h))
                let lr = r - 24
                let p = CGPoint(x: c.x + lr * cos(a), y: c.y + lr * sin(a))
                ctx.draw(Text(label)
                    .font(CoachTokens.mono(9))
                    .foregroundColor(CoachTokens.textFaint),
                         at: p, anchor: .center)
            }

            // Target pointer.
            let a = toRad(targetHour)
            let p = CGPoint(x: c.x + (r - 4) * cos(a), y: c.y + (r - 4) * sin(a))
            let pointerSize: CGFloat = isDragging ? 20 : 16
            let half = pointerSize / 2
            let pointerRect = CGRect(x: p.x - half, y: p.y - half,
                                     width: pointerSize, height: pointerSize)
            ctx.fill(Path(ellipseIn: pointerRect), with: .color(color))
            ctx.stroke(Path(ellipseIn: pointerRect), with: .color(.white), lineWidth: 2)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateTarget(from: value.location)
                    if !isDragging {
                        isDragging = true
                        hapticFeedback()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    hapticFeedback()
                }
        )
    }

    // MARK: - Gesture math

    private func updateTarget(from location: CGPoint) {
        let c = CGPoint(x: size / 2, y: size / 2)
        let dx = location.x - c.x
        let dy = location.y - c.y
        // Ignore taps very close to the center to prevent jitter.
        guard hypot(dx, dy) > 10 else { return }

        // atan2 gives angle from +x axis. Our 0h is at -π/2 (top), so
        // we shift by +π/2 and normalize to [0, 2π).
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        var hours = (angle / (2 * .pi)) * 24.0
        // Snap to nearest N minutes.
        let stepHours = Double(snapMinutes) / 60.0
        hours = (hours / stepHours).rounded() * stepHours
        if hours >= 24 { hours -= 24 }

        // Only trigger state write on actual change to avoid redundant
        // SwiftUI invalidations.
        if abs(hours - targetHour) >= stepHours * 0.5 {
            targetHour = hours
            hapticFeedback(style: .light)
        }
    }

    private func hapticFeedback(style: HapticStyle = .medium) {
        #if canImport(UIKit) && !os(watchOS)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        }
        generator.impactOccurred()
        #endif
    }

    private enum HapticStyle { case light, medium }
}
