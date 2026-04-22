# Coach Tab Redesign — "Bento + Editorial Feed" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **PROJECT RULE (from CLAUDE.md):** NEVER commit automatically. Only when user says "commitea" / "haz commit" / "commit". Every "Commit" step below is a SUGGESTION the user will trigger manually.

**Goal:** Replace the honeycomb-bubbles Coach tab with a scroll-based editorial layout: header + hero bento (score + MiniSpiral + last-7-nights bars) + 2×2 metric grid + 3 story cards (Lo que cambió / Lo que te propongo / Aprende), plus a custom CoachDock visible only on the Coach tab and 2 new sub-screens (Patrones, Plan).

**Architecture:** Pure SwiftUI views backed by a new `CoachDataAdapter` view model that reads from `SpiralStore.analysis` (composite, stats, enhancedCoach, coachInsight) and `sleepEpisodes`. Sub-screens navigate via `NavigationStack` inside `CoachHomeView`. Dock is a local overlay in `CoachHomeView`, not global. Preserves existing `CoachChatView` (restyled) and `CoachBubbleEngine` as data provider only — honeycomb visuals removed.

**Tech Stack:** SwiftUI (Canvas, Path/Shape, NavigationStack, ScrollView), SpiralKit (`SpiralStore`, `SpiralColors`, `Color(hex:)`), iOS 17+ Charts optional (we use Canvas/Path for control), `Localizable.xcstrings` (8 idiomas).

---

## File Map

### Create — Theme
| File | Responsibility |
|------|---------------|
| `spiral journey project/Theme/CoachTokens.swift` | SJ design tokens (hex, mono font, radii, spacing) — extends SpiralColors namespace for Coach only |

### Create — Coach main
| File | Responsibility |
|------|---------------|
| `spiral journey project/Views/Coach/CoachHomeView.swift` | Pantalla principal HybridA: header, hero bento, 2×2, feed editorial, dock overlay, NavigationStack |
| `spiral journey project/Views/Coach/CoachDock.swift` | Dock con 3 tabs compactos + pill "Pregúntame…" que abre chat |
| `spiral journey project/Views/Coach/CoachDataAdapter.swift` | `@Observable` VM que lee de SpiralStore y expone vm para las cards |

### Create — Coach shared components
| File | Responsibility |
|------|---------------|
| `spiral journey project/Views/Coach/Components/MiniSpiralView.swift` | Espiral polar 2D flat + N puntos quality (amarillo base + glow púrpura) |
| `spiral journey project/Views/Coach/Components/SparkSpiralView.swift` | Línea polar sola (para thumbnails y dock icon) |
| `spiral journey project/Views/Coach/Components/CoachMiniCard.swift` | Card 2×2 grid: título mono + valor grande + sub + children (sparkline/barras/striped habit) |
| `spiral journey project/Views/Coach/Components/CoachStoryCard.swift` | Card editorial con tag dot + título + children, variante `bright` púrpura |
| `spiral journey project/Views/Coach/Components/CoachSparklineView.swift` | Área path con gradient + puntos (usado en "Lo que cambió") |
| `spiral journey project/Views/Coach/Components/CoachBarSeriesView.swift` | 7 barras verticales con altura variable + highlight última |
| `spiral journey project/Views/Coach/Components/CoachTimeDialView.swift` | Dial circular 72px: track + arc púrpura + tick marks + icono luna |
| `spiral journey project/Views/Coach/Components/CoachTargetDialView.swift` | Dial circular 240px: 24h ticks, arco ventana óptima, pointer hora objetivo |

### Create — Coach sub-screens
| File | Responsibility |
|------|---------------|
| `spiral journey project/Views/Coach/Screens/CoachPatternsView.swift` | Heatmap 7×4 + correlación entreno + lista 4 insights |
| `spiral journey project/Views/Coach/Screens/CoachPlanView.swift` | TargetDial 240px + 4 pasos preparación + CTA "Activar recordatorio" |

### Modify
| File | Change |
|------|--------|
| `spiral journey project/Views/Tabs/CoachTab.swift` | Reemplazar body por `CoachHomeView()`, retirar honeycomb engine, conservar sheets de detail (jetLagSetup, coachChat, peerComparison) |
| `spiral journey project/Views/Coach/CoachChatView.swift` | Restyle header (avatar spark + "EN LÍNEA"), burbujas 4/16/16/16 radii, input bar flotante con mic |
| `spiral journey project/Localizable.xcstrings` | Añadir ~35 keys nuevas (coach.home.*, coach.patterns.*, coach.plan.*, coach.dock.*) en 8 idiomas |

### Delete (al final, cuando todo verificado)
| File | Reason |
|------|--------|
| `spiral journey project/Views/Coach/CoachBubbleViews.swift` | Honeycomb visuals replaced |
| `spiral journey project/Views/Coach/CoachBubbleEngine.swift` | Keep for 1 release as shim, borrar en Task 22 si no se usa |

---

## Design Tokens (handoff → code)

```
#0A0A1F → coachBg          (existe ~ SpiralColors.bg)
#12122B → coachBgSoft
#1A1A33 → coachCard        (surface)
#22224A → coachCardHi      (hero gradient top)
#8B5CF6 → coachPurple      (primary)
#6D28D9 → coachPurpleDim
#4C1D95 → coachPurpleDeep
#E5B951 → coachYellow      (spiral base / warning)
#5FB3D4 → coachBlue        (learn / patterns)
#B8B8C8 → coachSilver
#4ADE80 → coachGreen       (good state)
#F87171 → coachRed
borderHi = rgba(255,255,255,0.14)
border   = rgba(255,255,255,0.08)

Radii: sm=12 / md=16-18 / lg=22 / xl=26-32 / pill=9999
```

---

## Task 1: Coach design tokens

**Files:**
- Create: `spiral journey project/Theme/CoachTokens.swift`

- [ ] **Step 1.1: Create CoachTokens.swift**

```swift
import SwiftUI

/// Design tokens for the Coach tab redesign ("Medianoche" palette).
/// Dark-only. Hex values lifted verbatim from the design handoff.
/// Prefer these over `SpiralColors` INSIDE Coach views only — the rest of
/// the app keeps its semantic colors.
enum CoachTokens {

    // MARK: Background / surfaces
    static let bg          = Color(hex: "0A0A1F")
    static let bgSoft      = Color(hex: "12122B")
    static let card        = Color(hex: "1A1A33")
    static let cardHi      = Color(hex: "22224A")

    // MARK: Accents
    static let purple      = Color(hex: "8B5CF6")
    static let purpleDim   = Color(hex: "6D28D9")
    static let purpleDeep  = Color(hex: "4C1D95")
    static let yellow      = Color(hex: "E5B951")
    static let blue        = Color(hex: "5FB3D4")
    static let silver      = Color(hex: "B8B8C8")
    static let green       = Color(hex: "4ADE80")
    static let red         = Color(hex: "F87171")

    // MARK: Text
    static let text        = Color.white
    static let textDim     = Color.white.opacity(0.6)
    static let textFaint   = Color.white.opacity(0.3)

    // MARK: Border
    static let border      = Color.white.opacity(0.08)
    static let borderHi    = Color.white.opacity(0.14)

    // MARK: Radii
    static let rSm: CGFloat = 12
    static let rMd: CGFloat = 18
    static let rLg: CGFloat = 22
    static let rXl: CGFloat = 28
    static let rDock: CGFloat = 32

    // MARK: Mono font (SF Mono via system design: .monospaced)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: State-aware score colors (maps 0-100 score → paleta)
    static func accent(forScore s: Int) -> Color {
        switch s {
        case ...49: return yellow
        case 50...69: return purple
        default: return green
        }
    }
}
```

- [ ] **Step 1.2: Build iOS**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED. `Color(hex:)` already exists in `SpiralKit`.

- [ ] **Step 1.3: Suggest commit** (user triggers manually)

```
feat(coach): add CoachTokens design palette
```

---

## Task 2: MiniSpiralView component

**Files:**
- Create: `spiral journey project/Views/Coach/Components/MiniSpiralView.swift`

Replicates `MiniSpiral()` from `shared.jsx`: polar spiral with N turns, yellow base stroke, dotCount points of which ~quality fraction rendered as glowing purple, rest as dim yellow.

- [ ] **Step 2.1: Write MiniSpiralView**

```swift
import SwiftUI

/// Polar spiral rendered via Canvas. Used by the hero bento, chat avatar,
/// and learn-card thumbnails. NOT a replacement for SpiralView — it's a
/// decorative mini widget with a deterministic point distribution.
///
/// - Parameters:
///   - size: width/height in points (square).
///   - turns: number of full spiral turns (default 5).
///   - quality: 0–1 fraction of points rendered as "good" (purple glow).
///   - dotCount: how many points to scatter along the path.
///   - animate: rotate the whole shape 360° over 60s (loop).
///   - seed: determinism — same seed = same point layout.
struct MiniSpiralView: View {
    var size: CGFloat = 96
    var turns: Int = 5
    var quality: Double = 0.5
    var dotCount: Int = 24
    var animate: Bool = false
    var seed: UInt64 = 42

    @State private var rotation: Angle = .zero

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let c = CGPoint(x: r, y: r)
            let steps = 200

            // Spiral path (Archimedean, offset -π/2 so it starts at top).
            var path = Path()
            for i in 0...steps {
                let t = (Double(i) / Double(steps)) * Double(turns) * 2 * .pi
                let rr = (Double(i) / Double(steps)) * (Double(r) - 8)
                let x = Double(c.x) + rr * cos(t - .pi / 2)
                let y = Double(c.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(CoachTokens.yellow.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Deterministic dot layout.
            var rng = SplitMix64(seed: seed)
            for i in 0..<dotCount {
                let base = 20 + Int((Double(i) / Double(dotCount)) * Double(steps - 40))
                let jitter = Int(rng.nextDouble() * 6 - 3)
                let idx = max(0, min(steps, base + jitter))
                let tIdx = (Double(idx) / Double(steps)) * Double(turns) * 2 * .pi
                let rIdx = (Double(idx) / Double(steps)) * (Double(r) - 8)
                let x = Double(c.x) + rIdx * cos(tIdx - .pi / 2)
                let y = Double(c.y) + rIdx * sin(tIdx - .pi / 2)
                let good = rng.nextDouble() < quality
                let rect = CGRect(x: x - (good ? 1.8 : 2.2),
                                  y: y - (good ? 1.8 : 2.2),
                                  width: (good ? 3.6 : 4.4),
                                  height: (good ? 3.6 : 4.4))
                if good {
                    // Glow: draw a larger soft circle behind.
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                             with: .color(CoachTokens.purple.opacity(0.25)))
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(CoachTokens.purple.opacity(0.95)))
                } else {
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(CoachTokens.yellow.opacity(0.4)))
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(rotation)
        .onAppear {
            guard animate else { return }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
    }
}

/// Deterministic PRNG so dot layout is stable across renders.
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

#Preview("MiniSpiral 55") {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        MiniSpiralView(size: 96, turns: 5, quality: 0.55, dotCount: 26)
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2.2: Verify build + preview**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED. Open Preview in Xcode → see yellow spiral with 26 dots, ~55% purple.

- [ ] **Step 2.3: Suggest commit**

```
feat(coach): add MiniSpiralView polar widget
```

---

## Task 3: SparkSpiralView (line-only variant)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/SparkSpiralView.swift`

- [ ] **Step 3.1: Write SparkSpiralView**

```swift
import SwiftUI

/// Polar spiral as a single stroked path. No dots. Used for dock icon,
/// chat avatar, and learn-card thumbnails.
struct SparkSpiralView: View {
    var size: CGFloat = 22
    var turns: Int = 3
    var color: Color = CoachTokens.purple
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let c = CGPoint(x: r, y: r)
            var path = Path()
            let steps = 160
            for i in 0...steps {
                let t = (Double(i) / Double(steps)) * Double(turns) * 2 * .pi
                let rr = (Double(i) / Double(steps)) * (Double(r) - 4)
                let x = Double(c.x) + rr * cos(t - .pi / 2)
                let y = Double(c.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        SparkSpiralView(size: 64, turns: 4, color: CoachTokens.purple)
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 3.2: Build + preview**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3.3: Suggest commit**

```
feat(coach): add SparkSpiralView line variant
```

---

## Task 4: CoachSparklineView (area chart 7 points)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachSparklineView.swift`

Used inside the "LO QUE CAMBIÓ" story card. Shows 7-night bedtime with yellow area gradient + line + 7 points, last one enlarged with stroke.

- [ ] **Step 4.1: Write CoachSparklineView**

```swift
import SwiftUI

/// 7-point area chart with line on top and dots. Normalizes `values` to
/// fit the drawing bounds. Last point is rendered larger + stroked.
struct CoachSparklineView: View {
    var values: [Double]              // length N, arbitrary domain
    var color: Color = CoachTokens.yellow
    var height: CGFloat = 48
    var showAxisDays: Bool = true     // L M X J V S D labels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let pts = points(in: geo.size)
                ZStack {
                    // Area fill.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        p.addLine(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [color.opacity(0.45), color.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom))

                    // Line.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Dots.
                    ForEach(Array(pts.enumerated()), id: \.offset) { idx, pt in
                        let isLast = idx == pts.count - 1
                        Circle()
                            .fill(color)
                            .overlay {
                                if isLast {
                                    Circle().stroke(CoachTokens.bg, lineWidth: 2)
                                }
                            }
                            .frame(width: isLast ? 7 : 4, height: isLast ? 7 : 4)
                            .position(pt)
                    }
                }
            }
            .frame(height: height)

            if showAxisDays {
                HStack {
                    ForEach(["L","M","X","J","V","S","D"], id: \.self) { d in
                        Text(d).frame(maxWidth: .infinity)
                    }
                }
                .font(CoachTokens.mono(9))
                .foregroundStyle(CoachTokens.textFaint)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(0.0001, maxV - minV)
        let stepX = size.width / CGFloat(max(1, values.count - 1))
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = (v - minV) / span
            let y = size.height - CGFloat(norm) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.card.ignoresSafeArea()
        CoachSparklineView(values: [8, 10, 18, 30, 38, 34, 40])
            .padding()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 4.2: Build**
Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

- [ ] **Step 4.3: Suggest commit** → `feat(coach): add CoachSparklineView`

---

## Task 5: CoachBarSeriesView (7 vertical bars)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachBarSeriesView.swift`

Used in: hero bento (last 7 nights durations), and in CoachMiniCard variants (consistency — purple bars with yellow when under 0.5).

- [ ] **Step 5.1: Write CoachBarSeriesView**

```swift
import SwiftUI

/// 7 vertical bars with height proportional to value (0–1). Last bar
/// highlighted. Bar color switches to `lowColor` when value < 0.5.
struct CoachBarSeriesView: View {
    var values: [Double]              // 0...1
    var barHeight: CGFloat = 22
    var color: Color = CoachTokens.purple.opacity(0.7)
    var lowColor: Color = CoachTokens.yellow.opacity(0.7)
    var highlightLast: Color = CoachTokens.yellow
    var gap: CGFloat = 3
    var cornerRadius: CGFloat = 2

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                let isLast = idx == values.count - 1
                let clamped = min(max(v, 0), 1)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isLast ? highlightLast : (v < 0.5 ? lowColor : color))
                    .frame(height: max(2, barHeight * CGFloat(clamped)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight, alignment: .bottom)
    }
}

#Preview {
    ZStack {
        CoachTokens.cardHi.ignoresSafeArea()
        CoachBarSeriesView(values: [0.6, 0.4, 0.35, 0.9, 0.7, 0.5, 0.45])
            .padding()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 5.2: Build + suggest commit** → `feat(coach): add CoachBarSeriesView`

---

## Task 6: CoachMiniCard (2×2 grid cell)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachMiniCard.swift`

- [ ] **Step 6.1: Write CoachMiniCard**

```swift
import SwiftUI

/// One cell of the 2×2 metric bento. Mono title + large value + sub +
/// optional bottom slot (sparkline, bars, habit stripes). `accent = true`
/// paints the whole card with a yellow gradient (for HÁBITO).
struct CoachMiniCard<Bottom: View>: View {
    let title: String          // ALL CAPS — "DURACIÓN"
    let value: String          // "4.5h"
    let sub: String            // "anoche · -1.2h"
    var valueColor: Color = CoachTokens.yellow
    var iconSystem: String? = nil
    var accent: Bool = false
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(title)
                    .font(CoachTokens.mono(9))
                    .foregroundStyle(CoachTokens.textDim)
                    .tracking(1)
                Spacer()
                if let sys = iconSystem {
                    Image(systemName: sys)
                        .font(.system(size: 13))
                        .foregroundStyle(valueColor)
                }
            }
            Text(value)
                .font(CoachTokens.mono(20, weight: .bold))
                .foregroundStyle(valueColor)
                .padding(.top, 4)
            Text(sub)
                .font(CoachTokens.sans(10))
                .foregroundStyle(CoachTokens.textDim)
                .padding(.top, 2)
            bottom()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rMd, style: .continuous)
                .stroke(accent ? CoachTokens.yellow.opacity(0.22) : CoachTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rMd, style: .continuous))
    }

    private var cardBackground: some View {
        Group {
            if accent {
                LinearGradient(
                    colors: [CoachTokens.yellow.opacity(0.15), CoachTokens.yellow.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                CoachTokens.card
            }
        }
    }
}

extension CoachMiniCard where Bottom == EmptyView {
    init(title: String, value: String, sub: String,
         valueColor: Color = CoachTokens.yellow,
         iconSystem: String? = nil, accent: Bool = false) {
        self.init(title: title, value: value, sub: sub,
                  valueColor: valueColor, iconSystem: iconSystem, accent: accent,
                  bottom: { EmptyView() })
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            CoachMiniCard(title: "DURACIÓN", value: "4.5h", sub: "anoche · -1.2h") {
                CoachSparklineView(values: [8,10,18,30,38,34,40], height: 26, showAxisDays: false)
                    .padding(.top, 6)
            }
            CoachMiniCard(title: "CONSISTENCIA", value: "32", sub: "/100 · irregular",
                          valueColor: CoachTokens.purple) {
                CoachBarSeriesView(values: [0.7, 0.9, 0.4, 0.3, 0.85, 0.5, 0.4],
                                   barHeight: 22,
                                   color: CoachTokens.purple,
                                   highlightLast: CoachTokens.purple)
                    .padding(.top, 6)
            }
            CoachMiniCard(title: "PATRONES", value: "3 tardes", sub: "esta semana",
                          valueColor: CoachTokens.blue, iconSystem: "waveform")
            CoachMiniCard(title: "HÁBITO", value: "5", sub: "días seguidos",
                          valueColor: CoachTokens.yellow, accent: true) {
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < 5 ? CoachTokens.yellow : Color.white.opacity(0.08))
                            .frame(height: 4)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 6.2: Build + suggest commit** → `feat(coach): add CoachMiniCard 2x2 grid cell`

---

## Task 7: CoachStoryCard (editorial chapter)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachStoryCard.swift`

- [ ] **Step 7.1: Write CoachStoryCard**

```swift
import SwiftUI

/// Editorial card with colored dot + tag label in mono ALL CAPS, followed
/// by body content. `bright = true` paints a purple gradient background
/// (used for "LO QUE TE PROPONGO").
struct CoachStoryCard<Content: View>: View {
    let tag: String
    let tagColor: Color
    var bright: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(tagColor).frame(width: 4, height: 4)
                Text(tag)
                    .font(CoachTokens.mono(10, weight: .medium))
                    .foregroundStyle(tagColor)
                    .tracking(1.3)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous)
                .stroke(bright ? CoachTokens.purple.opacity(0.25) : CoachTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous))
    }

    private var background: some View {
        Group {
            if bright {
                LinearGradient(
                    colors: [CoachTokens.purple.opacity(0.14), CoachTokens.card],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                CoachTokens.card
            }
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        VStack(spacing: 10) {
            CoachStoryCard(tag: "LO QUE CAMBIÓ", tagColor: CoachTokens.yellow) {
                Text("Te acuestas **1h 47m más tarde** que la semana pasada.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            CoachStoryCard(tag: "LO QUE TE PROPONGO", tagColor: CoachTokens.purple, bright: true) {
                Text("Esta noche, antes de la 01:30.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 7.2: Build + suggest commit** → `feat(coach): add CoachStoryCard`

---

## Task 8: CoachTimeDialView (72px inline)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachTimeDialView.swift`

Arc púrpura sobre track gris 24h + 4 tick marks + icono luna centrado.

- [ ] **Step 8.1: Write CoachTimeDialView**

```swift
import SwiftUI

/// Small 72-pt dial showing an optimal-window arc against a 24h clock.
/// - windowStart/windowEnd: hours in 0..24 (e.g. 1.25, 1.75).
struct CoachTimeDialView: View {
    var size: CGFloat = 72
    var windowStart: Double = 1.25
    var windowEnd: Double = 1.75
    var color: Color = CoachTokens.purple

    var body: some View {
        Canvas { ctx, _ in
            let r = size / 2
            let c = CGPoint(x: r, y: r)
            let trackRadius = r - 6

            // Track.
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: c.x - trackRadius, y: c.y - trackRadius,
                    width: trackRadius * 2, height: trackRadius * 2)),
                with: .color(Color.white.opacity(0.08)),
                lineWidth: 3)

            // Optimal window arc.
            let toRad = { (h: Double) -> Double in (h / 24.0) * 2 * .pi - .pi / 2 }
            let a1 = toRad(windowStart), a2 = toRad(windowEnd)
            var arc = Path()
            arc.addArc(center: c, radius: trackRadius,
                       startAngle: .radians(a1), endAngle: .radians(a2),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Quarter hour ticks.
            for h in [0.0, 6.0, 12.0, 18.0] {
                let a = toRad(h)
                let p = CGPoint(x: c.x + (r - 2) * cos(a),
                                y: c.y + (r - 2) * sin(a))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                         with: .color(Color.white.opacity(0.3)))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        CoachTimeDialView()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 8.2: Build + suggest commit** → `feat(coach): add CoachTimeDialView`

---

## Task 9: CoachDataAdapter (view model)

**Files:**
- Create: `spiral journey project/Views/Coach/CoachDataAdapter.swift`

Reads from `SpiralStore` (already wired into `CoachTab` via `@Environment`), produces data structs that the views consume. No logic duplication with `CoachBubbleEngine` — this is pure read-path.

- [ ] **Step 9.1: Write CoachDataAdapter**

```swift
import Foundation
import SwiftUI
import SpiralKit

/// Adapter that converts SpiralStore state into plain structs the new
/// Coach views can render. Keep this free of SwiftUI View types so it's
/// trivially testable.
@Observable
@MainActor
final class CoachDataAdapter {

    // MARK: - Output structs

    struct HeroData {
        let score: Int                // 0...100, composite
        let todayLabel: String        // "ESTA NOCHE"
        let insightTitle: String      // "Tu ritmo pide constancia"
        let last7Bars: [Double]       // 0...1 durations normalized
        let last7Subtitle: String     // "7 NOCHES · -1.2h MEDIA"
        let accent: Color             // purple / yellow / green
    }

    struct BentoData {
        let durationValue: String     // "4.5h"
        let durationSub: String       // "anoche · -1.2h"
        let durationSeries: [Double]  // 7 points bedtime latenss
        let consistencyValue: String  // "32"
        let consistencySub: String    // "/100 · irregular"
        let consistencyBars: [Double] // 0...1 (SRI daily)
        let patternsValue: String     // "3 tardes" or "estable"
        let patternsSub: String
        let habitValue: String        // "5"
        let habitSub: String          // "días seguidos"
        let habitStripes: [Bool]      // 7 days L-M-X-J-V-S-D
    }

    struct ProposalData {
        let title: String             // "Esta noche, antes de la 01:30."
        let window: String            // "01:15 – 01:45"
        let chronotypeSub: String     // "Cronotipo: nocturno moderado"
        let dialStart: Double         // hours 0..24
        let dialEnd: Double
    }

    struct ChangeData {
        let headline: String          // "Te acuestas 1h 47m más tarde..."
        let highlightedFragment: String  // "1h 47m más tarde"
        let sparkValues: [Double]
        let rangeLabel: String        // "00:00 → 03:00"
    }

    struct LearnData {
        let title: String
        let subtitle: String          // "Lectura breve"
    }

    // MARK: - Inputs

    let store: SpiralStore

    init(store: SpiralStore) { self.store = store }

    // MARK: - Derived

    var hero: HeroData {
        let score = store.analysis.composite
        let durations = lastNDurations(n: 7)
        let mean = durations.isEmpty ? 0 : durations.reduce(0,+) / Double(durations.count)
        let yesterday = durations.last ?? mean
        let diff = yesterday - mean
        let diffStr = String(format: "%+0.1fh", diff)
        return HeroData(
            score: score,
            todayLabel: "ESTA NOCHE",
            insightTitle: store.analysis.coachInsight?.title ?? "Tu ritmo pide constancia",
            last7Bars: normalizeBars(durations),
            last7Subtitle: "7 NOCHES · \(diffStr) MEDIA",
            accent: CoachTokens.accent(forScore: score))
    }

    var bento: BentoData {
        let durations = lastNDurations(n: 7)
        let bedtimes = lastNBedtimeLatenessNorm(n: 7)
        let sri = store.analysis.stats.sri ?? 0
        let sriDaily = lastNSRIDaily(n: 7)
        let streak = store.analysis.enhancedCoach?.streak.currentStreak ?? 0
        let habitStripes = lastNHabitCompleted(n: 7)
        let patterns = store.analysis.enhancedCoach?.patterns.count ?? 0
        return BentoData(
            durationValue: String(format: "%.1fh", durations.last ?? 0),
            durationSub: durationSubtitle(durations: durations),
            durationSeries: bedtimes,
            consistencyValue: "\(Int(sri))",
            consistencySub: "/100 · \(sriLabel(sri))",
            consistencyBars: sriDaily,
            patternsValue: patterns > 0 ? "\(patterns) patrones" : "estable",
            patternsSub: patterns > 0 ? "esta semana" : "sin cambios",
            habitValue: "\(streak)",
            habitSub: "días seguidos",
            habitStripes: habitStripes)
    }

    var proposal: ProposalData? {
        // Ventana óptima basada en cronotipo: ±15 min alrededor del
        // chronotypeResult.suggestedBedtime (existe en SpiralStore).
        guard let target = store.chronotypeResult?.suggestedBedtime else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: target)
        let hours = Double(comps.hour ?? 1) + Double(comps.minute ?? 30) / 60.0
        let start = hours - 0.25
        let end = hours + 0.25
        let hh = Int(hours), mm = Int((hours - Double(hh)) * 60)
        return ProposalData(
            title: "Esta noche, antes de la \(String(format: "%02d:%02d", hh, mm)).",
            window: "\(formatHour(start)) – \(formatHour(end))",
            chronotypeSub: "Cronotipo: \(store.chronotypeResult?.label ?? "en cálculo")",
            dialStart: start, dialEnd: end)
    }

    var change: ChangeData {
        let durations = lastNDurations(n: 7)
        let deltaThis = durations.suffix(3).reduce(0,+) / 3.0
        let deltaPrev = durations.prefix(3).reduce(0,+) / 3.0
        let diffMin = Int((deltaThis - deltaPrev) * 60)
        let label = diffMin < 0
            ? "\(abs(diffMin / 60))h \(abs(diffMin) % 60)m más tarde"
            : "\(diffMin / 60)h \(diffMin % 60)m antes"
        return ChangeData(
            headline: "Te acuestas \(label) que la semana pasada.",
            highlightedFragment: label,
            sparkValues: normalizeBars(durations).map { 1 - $0 },  // "más tarde" = más abajo
            rangeLabel: "00:00 → 03:00")
    }

    var learn: LearnData {
        // Pull a rotating educational snippet. Keep default until Learn
        // content is wired in.
        LearnData(
            title: "Jet lag social: por qué el domingo te pasa factura el martes",
            subtitle: "Lectura breve")
    }

    // MARK: - Helpers

    private func lastNDurations(n: Int) -> [Double] {
        let eps = store.sleepEpisodes.suffix(n)
        return eps.map { $0.durationHours }
    }

    private func lastNBedtimeLatenessNorm(n: Int) -> [Double] {
        // 0 = early (00:00), 1 = late (03:30). Clamp.
        let eps = store.sleepEpisodes.suffix(n)
        return eps.map { ep in
            let h = Calendar.current.component(.hour, from: ep.start)
            let m = Calendar.current.component(.minute, from: ep.start)
            let hours = Double(h) + Double(m) / 60.0
            // Map 22 → 0 and 4 → 1 (wrap-aware).
            let norm = hours >= 22 ? (hours - 22) / 6.0 : (hours + 2) / 6.0
            return min(max(norm, 0), 1)
        }
    }

    private func lastNSRIDaily(n: Int) -> [Double] {
        // The app only stores aggregated SRI; approximate per-day with a
        // rolling window over the last N durations vs personal mean.
        let durations = lastNDurations(n: n)
        guard let mean = durations.first.map({ _ in
            durations.reduce(0, +) / Double(durations.count)
        }), mean > 0 else { return Array(repeating: 0.5, count: n) }
        return durations.map { 1 - min(abs($0 - mean) / mean, 1) }
    }

    private func lastNHabitCompleted(n: Int) -> [Bool] {
        // Map the last N days via `microHabitCompletions`. Keys are
        // "<issueKey>.<cycleDay>". We just want on/off per day.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).map { offset in
            guard let date = cal.date(byAdding: .day, value: -(n - 1 - offset), to: today)
            else { return false }
            let key = "\(cal.component(.day, from: date))"
            return store.microHabitCompletions.contains { $0.key.contains(key) && $0.value }
        }
    }

    private func normalizeBars(_ values: [Double]) -> [Double] {
        guard let maxV = values.max(), maxV > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / maxV }
    }

    private func durationSubtitle(durations: [Double]) -> String {
        guard let last = durations.last, durations.count >= 2 else {
            return "anoche"
        }
        let mean = durations.dropLast().reduce(0,+) / Double(max(1, durations.count - 1))
        let diff = last - mean
        return String(format: "anoche · %+0.1fh", diff)
    }

    private func sriLabel(_ sri: Double) -> String {
        switch sri {
        case ...40: return "irregular"
        case 41...60: return "variable"
        case 61...80: return "consistente"
        default: return "sólido"
        }
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        return String(format: "%02d:%02d", (hh + 24) % 24, (mm + 60) % 60)
    }
}
```

- [ ] **Step 9.2: Sanity-check property access**

The adapter references: `store.analysis.composite`, `store.analysis.coachInsight?.title`, `store.analysis.stats.sri`, `store.analysis.enhancedCoach?.streak.currentStreak`, `store.analysis.enhancedCoach?.patterns.count`, `store.sleepEpisodes`, `store.chronotypeResult?.suggestedBedtime`, `store.chronotypeResult?.label`, `store.microHabitCompletions`.

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

Expected: BUILD SUCCEEDED.

**If build fails with "no member X":** the property name differs. Grep the actual type:
```
grep -rn "struct ChronotypeResult\|var suggestedBedtime\|var label" "spiral journey project/"
grep -rn "struct SleepEpisode" SpiralKit/
```
Adjust adapter accordingly. Do NOT invent properties.

- [ ] **Step 9.3: Suggest commit** → `feat(coach): add CoachDataAdapter view model`

---

## Task 10: CoachHomeView scaffold (header + scroll)

**Files:**
- Create: `spiral journey project/Views/Coach/CoachHomeView.swift`

Builds top-to-bottom. Tasks 11-14 fill the body.

- [ ] **Step 10.1: Write CoachHomeView scaffold**

```swift
import SwiftUI
import SpiralKit

/// Coach tab redesign — HybridA layout.
/// Scroll: header, hero bento, 2×2 metrics, editorial feed, dock overlay.
struct CoachHomeView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var showChat = false
    @State private var showPatterns = false
    @State private var showPlan = false

    private var adapter: CoachDataAdapter { CoachDataAdapter(store: store) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CoachTokens.bg.ignoresSafeArea()

                // Ambient purple glow top-right.
                RadialGradient(
                    colors: [CoachTokens.purple.opacity(0.18), .clear],
                    center: UnitPoint(x: 1.1, y: -0.05),
                    startRadius: 20, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        heroBento
                        bentoGrid
                        divider
                        storyLoQueCambio
                        storyLoQuePropongo
                        storyAprende
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)  // breathing room under dock
                }

                CoachDock(
                    onAskTap: { showChat = true },
                    onTabTap: { _ in }      // dock doesn't switch tabs here
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .sheet(isPresented: $showChat) { CoachChatView() }
            .sheet(isPresented: $showPlan) { CoachPlanView() }
            .navigationDestination(isPresented: $showPatterns) { CoachPatternsView() }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(todayLabel)
                .font(CoachTokens.mono(13))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(0.4)
            Text(greeting)
                .font(CoachTokens.sans(28, weight: .bold))
                .foregroundStyle(.white)
                .tracking(-0.5)
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(CoachTokens.border).frame(height: 1)
            Text(String(localized: "coach.home.feed.divider", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1.5)
            Rectangle().fill(CoachTokens.border).frame(height: 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
    }

    // Filled in Tasks 11–14.
    private var heroBento: some View { EmptyView() }
    private var bentoGrid: some View { EmptyView() }
    private var storyLoQueCambio: some View { EmptyView() }
    private var storyLoQuePropongo: some View { EmptyView() }
    private var storyAprende: some View { EmptyView() }

    // MARK: - Copy helpers

    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE · d MMM"
        return fmt.string(from: Date()).uppercased()
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let username = store.userName ?? ""
        let base: String
        switch h {
        case 5..<12: base = "Buenos días"
        case 12..<20: base = "Buenas tardes"
        default: base = "Buenas noches"
        }
        return username.isEmpty ? base : "\(base), \(username)"
    }
}

#Preview {
    CoachHomeView()
        .environment(SpiralStore.preview)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 10.2: Check SpiralStore.userName exists**

If `store.userName` isn't a property, use `store.profile?.name` or fall back to empty. Run:
```
grep -n "var userName\|var profile" "spiral journey project/Services/SpiralStore.swift"
```
Adjust line 117 of `CoachHomeView` accordingly.

- [ ] **Step 10.3: Check SpiralStore.preview exists**

If not, replace `.environment(SpiralStore.preview)` with `.environment(SpiralStore(modelContext: ModelContext(try! ModelContainer(for: SleepEpisode.self))))` or whatever the project uses elsewhere. Search:
```
grep -rn "SpiralStore.preview\|SpiralStore(" "spiral journey project/Views/"
```

- [ ] **Step 10.4: Build**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 10.5: Suggest commit** → `feat(coach): add CoachHomeView scaffold`

---

## Task 11: CoachHomeView hero bento

**Files:**
- Modify: `spiral journey project/Views/Coach/CoachHomeView.swift`

- [ ] **Step 11.1: Replace `heroBento` stub**

```swift
private var heroBento: some View {
    let h = adapter.hero
    return ZStack(alignment: .topLeading) {
        LinearGradient(
            colors: [CoachTokens.cardHi, CoachTokens.card],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        RadialGradient(
            colors: [CoachTokens.purple.opacity(0.25), .clear],
            center: UnitPoint(x: 0.85, y: 0.30),
            startRadius: 10, endRadius: 160)
        .allowsHitTesting(false)

        HStack(alignment: .center, spacing: 12) {
            ZStack {
                MiniSpiralView(size: 96, turns: 5, quality: Double(h.score) / 100, dotCount: 26)
                VStack(spacing: 1) {
                    Text("\(h.score)")
                        .font(CoachTokens.mono(28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("SCORE")
                        .font(CoachTokens.mono(8))
                        .foregroundStyle(CoachTokens.textDim)
                        .tracking(1)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 3) {
                Text(h.todayLabel)
                    .font(CoachTokens.mono(10))
                    .foregroundStyle(CoachTokens.yellow)
                    .tracking(1)
                Text(h.insightTitle)
                    .font(CoachTokens.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.top, 3)
                CoachBarSeriesView(
                    values: h.last7Bars,
                    barHeight: 22,
                    color: CoachTokens.purple.opacity(0.7),
                    lowColor: CoachTokens.yellow.opacity(0.7),
                    highlightLast: h.accent)
                .padding(.top, 8)
                Text(h.last7Subtitle)
                    .font(CoachTokens.mono(10))
                    .foregroundStyle(CoachTokens.textDim)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }
    .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous)
            .stroke(CoachTokens.borderHi, lineWidth: 1))
}
```

- [ ] **Step 11.2: Build + visual check**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED. Preview must show spiral + score + "ESTA NOCHE" header + 7 bars.

- [ ] **Step 11.3: Suggest commit** → `feat(coach): fill hero bento with MiniSpiral + last-7 bars`

---

## Task 12: CoachHomeView 2×2 metric grid

**Files:**
- Modify: `spiral journey project/Views/Coach/CoachHomeView.swift`

- [ ] **Step 12.1: Replace `bentoGrid` stub**

```swift
private var bentoGrid: some View {
    let b = adapter.bento
    return LazyVGrid(columns: [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible())
    ], spacing: 10) {
        CoachMiniCard(title: "DURACIÓN", value: b.durationValue, sub: b.durationSub,
                      valueColor: CoachTokens.yellow) {
            CoachSparklineView(values: b.durationSeries, color: CoachTokens.yellow,
                               height: 26, showAxisDays: false)
                .padding(.top, 6)
        }

        CoachMiniCard(title: "CONSISTENCIA", value: b.consistencyValue, sub: b.consistencySub,
                      valueColor: CoachTokens.purple) {
            CoachBarSeriesView(values: b.consistencyBars, barHeight: 22,
                               color: CoachTokens.purple,
                               lowColor: CoachTokens.yellow,
                               highlightLast: CoachTokens.purple)
                .padding(.top, 6)
        }

        Button {
            showPatterns = true
        } label: {
            CoachMiniCard(title: "PATRONES", value: b.patternsValue, sub: b.patternsSub,
                          valueColor: CoachTokens.blue, iconSystem: "waveform")
        }
        .buttonStyle(.plain)

        CoachMiniCard(title: "HÁBITO", value: b.habitValue, sub: b.habitSub,
                      valueColor: CoachTokens.yellow, accent: true) {
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < b.habitStripes.filter { $0 }.count
                              ? CoachTokens.yellow
                              : Color.white.opacity(0.08))
                        .frame(height: 4)
                }
            }
            .padding(.top, 6)
        }
    }
}
```

- [ ] **Step 12.2: Build + suggest commit** → `feat(coach): 2x2 metric bento grid`

---

## Task 13: CoachHomeView story cards

**Files:**
- Modify: `spiral journey project/Views/Coach/CoachHomeView.swift`

- [ ] **Step 13.1: Replace the three story stubs**

```swift
private var storyLoQueCambio: some View {
    let c = adapter.change
    return CoachStoryCard(tag: "LO QUE CAMBIÓ", tagColor: CoachTokens.yellow) {
        Text(LocalizedStringResource(stringLiteral: c.headline))
            .font(CoachTokens.sans(16, weight: .semibold))
            .foregroundStyle(.white)
            .lineSpacing(2)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HORA DE ACOSTARSE")
                Spacer()
                Text(c.rangeLabel)
            }
            .font(CoachTokens.mono(9))
            .foregroundStyle(CoachTokens.textDim)
            .tracking(0.5)
            .padding(.bottom, 6)

            CoachSparklineView(values: c.sparkValues, height: 48)
        }
        .padding(12)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 12)
    }
}

private var storyLoQuePropongo: some View {
    guard let p = adapter.proposal else { return AnyView(EmptyView()) }
    return AnyView(
        CoachStoryCard(tag: "LO QUE TE PROPONGO", tagColor: CoachTokens.purple, bright: true) {
            Text(p.title)
                .font(CoachTokens.sans(16, weight: .semibold))
                .foregroundStyle(.white)
                .lineSpacing(2)

            HStack(alignment: .center, spacing: 14) {
                CoachTimeDialView(size: 72, windowStart: p.dialStart, windowEnd: p.dialEnd)
                VStack(alignment: .leading, spacing: 1) {
                    Text("VENTANA ÓPTIMA")
                        .font(CoachTokens.mono(9))
                        .foregroundStyle(CoachTokens.textDim)
                        .tracking(1)
                    Text(p.window)
                        .font(CoachTokens.mono(20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(p.chronotypeSub)
                        .font(CoachTokens.sans(11))
                        .foregroundStyle(CoachTokens.textDim)
                        .padding(.top, 3)
                    HStack(spacing: 5) {
                        Button("Recuérdamelo") { showPlan = true }
                            .buttonStyle(CoachPillButtonStyle(primary: true))
                        Button("Ajustar") { /* TODO nav to chronotype settings */ }
                            .buttonStyle(CoachPillButtonStyle(primary: false))
                    }
                    .padding(.top, 9)
                }
            }
            .padding(.top, 12)
        }
    )
}

private var storyAprende: some View {
    let l = adapter.learn
    return CoachStoryCard(tag: "APRENDE · 3 MIN", tagColor: CoachTokens.blue) {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(
                        colors: [CoachTokens.blue.opacity(0.27), CoachTokens.purpleDeep.opacity(0.27)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).stroke(CoachTokens.border, lineWidth: 1))
                SparkSpiralView(size: 38, turns: 4, color: CoachTokens.blue, lineWidth: 1.5)
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.title)
                    .font(CoachTokens.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Text(l.subtitle)
                    .font(CoachTokens.sans(11))
                    .foregroundStyle(CoachTokens.textDim)
            }
        }
    }
}

private struct CoachPillButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CoachTokens.sans(12, weight: .medium))
            .foregroundStyle(primary ? .white : CoachTokens.textDim)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(primary ? CoachTokens.purple : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
```

- [ ] **Step 13.2: Build + visual check**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 13.3: Suggest commit** → `feat(coach): 3 editorial story cards`

---

## Task 14: CoachDock

**Files:**
- Create: `spiral journey project/Views/Coach/CoachDock.swift`

- [ ] **Step 14.1: Write CoachDock**

```swift
import SwiftUI

/// Floating dock shown ONLY inside CoachHomeView. Replaces the visual
/// footprint of the system tab bar for this screen. 3 sibling tabs are
/// decorative stubs (they visually match but do NOT switch tabs — the
/// outer TabView still handles real tab changes when the user taps those
/// zones of the screen; to switch tabs they use the real tab bar that
/// sits behind this overlay). The active pill is Coach + "Pregúntame…".
struct CoachDock: View {
    var onAskTap: () -> Void
    var onTabTap: (Int) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            tabButton(index: 0, icon: "moon.stars", label: "Espiral")
            tabButton(index: 1, icon: "chart.line.uptrend.xyaxis", label: "Tendencias")
            tabButton(index: 2, icon: "gearshape", label: "Ajustes")

            // Active Coach pill.
            Button(action: onAskTap) {
                HStack(spacing: 8) {
                    SparkSpiralView(size: 22, turns: 3, color: CoachTokens.purple, lineWidth: 1.6)
                    Text("Pregúntame…")
                        .font(CoachTokens.sans(12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(CoachTokens.purple)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    .shadow(color: CoachTokens.purple.opacity(0.4), radius: 8, y: 2)
                }
                .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 6))
                .background(
                    LinearGradient(
                        colors: [CoachTokens.purple.opacity(0.28), CoachTokens.purpleDeep.opacity(0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 26).stroke(CoachTokens.purple.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CoachTokens.rDock).fill(.ultraThinMaterial)
                Color(hex: "1E1E3C").opacity(0.65)
            })
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rDock)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rDock))
        .shadow(color: .black.opacity(0.45), radius: 32, y: 8)
    }

    private func tabButton(index: Int, icon: String, label: String) -> some View {
        Button {
            onTabTap(index)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(CoachTokens.textDim)
                Text(label)
                    .font(CoachTokens.sans(9, weight: .medium))
                    .foregroundStyle(CoachTokens.textDim)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        CoachTokens.bg.ignoresSafeArea()
        CoachDock(onAskTap: {})
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
    }
    .preferredColorScheme(.dark)
}
```

**Note:** the sibling-tab icons in the dock are decorative. The real TabView sits behind and handles tab switches through the user's existing habit. We consciously do NOT route tab changes through `onTabTap` to keep the dock self-contained.

- [ ] **Step 14.2: Build + suggest commit** → `feat(coach): add CoachDock overlay`

---

## Task 15: Hide system tab bar when Coach tab is active

**Files:**
- Modify: `spiral journey project/ContentView.swift`

The CoachDock visually replaces the tab bar INSIDE the Coach tab only. We hide the system tab bar when Coach is selected, show it for the other three.

- [ ] **Step 15.1: Inspect current ContentView**

Read: `spiral journey project/ContentView.swift:1-160`

Verify the structure: `TabView(selection: $selectedTab) { … }`. Identify where `.toolbar(.visible, for: .tabBar)` or similar could be added.

- [ ] **Step 15.2: Toggle tab bar visibility**

Find the line where the `CoachTab` view is attached (handoff indicated line ~40-45). Wrap or modify that tab content:

```swift
CoachTab()
    .tag(AppTab.coach)
    .toolbar(selectedTab == .coach ? .hidden : .visible, for: .tabBar)
```

And on the other three tabs:
```swift
SpiralTab() .tag(AppTab.spiral).toolbar(.visible, for: .tabBar)
TrendsTab() .tag(AppTab.trends).toolbar(.visible, for: .tabBar)
SettingsTab().tag(AppTab.settings).toolbar(.visible, for: .tabBar)
```

**If `.toolbar(_:for:)` doesn't accept conditional `.hidden/.visible`,** use a state-scoped modifier at the `TabView` level:
```swift
.toolbar(selectedTab == .coach ? .hidden : .visible, for: .tabBar)
```
at the TabView, not each tab.

- [ ] **Step 15.3: Build + run**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

Launch on simulator. Navigate Coach → tab bar hides, dock visible. Navigate to Espiral → system tab bar visible.

- [ ] **Step 15.4: Suggest commit** → `feat(coach): hide system tab bar on Coach tab`

---

## Task 16: Swap CoachTab to use CoachHomeView

**Files:**
- Modify: `spiral journey project/Views/Tabs/CoachTab.swift`

CoachTab is currently 1092 lines of honeycomb layout. We replace its body with CoachHomeView, keep the sheets infrastructure.

- [ ] **Step 16.1: Read current CoachTab**

Read: `spiral journey project/Views/Tabs/CoachTab.swift:1-80`

Note the sheets: `showJetLagSetup`, `showCoachChat`, `showPeerComparison`, `showDetail`. These are driven by the honeycomb. After the swap, navigation originates from `CoachHomeView`, so CoachTab simplifies to a thin wrapper.

- [ ] **Step 16.2: Replace body**

Replace the entire file (or the `body` property) with:

```swift
import SwiftUI
import SpiralKit

struct CoachTab: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        CoachHomeView()
    }
}
```

The old sheet presenters now live inside `CoachHomeView` (Task 10) and inside each NavigationDestination.

- [ ] **Step 16.3: Build + run**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

Expected: BUILD SUCCEEDED. Launch → Coach tab shows new home view.

- [ ] **Step 16.4: Suggest commit** → `refactor(coach): replace CoachTab body with CoachHomeView`

---

## Task 17: CoachTargetDialView (240px dial for Plan screen)

**Files:**
- Create: `spiral journey project/Views/Coach/Components/CoachTargetDialView.swift`

- [ ] **Step 17.1: Write CoachTargetDialView**

```swift
import SwiftUI

/// Large 240pt dial for the Plan screen. Draws full 24-hour clock with
/// ticks, a glowing purple arc for the optimal window, and a pointer
/// dot at the target hour.
struct CoachTargetDialView: View {
    var size: CGFloat = 240
    var windowStart: Double = 1.25
    var windowEnd: Double = 1.75
    var targetHour: Double = 1.5
    var color: Color = CoachTokens.purple

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

            // Optimal window arc.
            let toRad = { (h: Double) -> Double in (h / 24.0) * 2 * .pi - .pi / 2 }
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
            let pointerRect = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: pointerRect), with: .color(color))
            ctx.stroke(Path(ellipseIn: pointerRect), with: .color(.white), lineWidth: 2)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        CoachTargetDialView()
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 17.2: Build + suggest commit** → `feat(coach): add CoachTargetDialView 240pt`

---

## Task 18: CoachPlanView (sub-screen)

**Files:**
- Create: `spiral journey project/Views/Coach/Screens/CoachPlanView.swift`

- [ ] **Step 18.1: Write CoachPlanView**

```swift
import SwiftUI
import SpiralKit

struct CoachPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpiralStore.self) private var store

    private var adapter: CoachDataAdapter { CoachDataAdapter(store: store) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.purple.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.5, y: -0.2),
                           startRadius: 40, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    header
                    dialSection
                    headline
                    preparationList
                    Spacer().frame(height: 100)
                }
            }

            bottomCTA
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachTokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Text("PLAN · ESTA NOCHE")
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
            Spacer()
            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var dialSection: some View {
        VStack(spacing: 0) {
            if let p = adapter.proposal {
                ZStack {
                    CoachTargetDialView(
                        size: 240,
                        windowStart: p.dialStart,
                        windowEnd: p.dialEnd,
                        targetHour: (p.dialStart + p.dialEnd) / 2)
                    VStack(spacing: -2) {
                        Text("ACUÉSTATE A LAS")
                            .font(CoachTokens.mono(10))
                            .foregroundStyle(CoachTokens.purple)
                            .tracking(1.5)
                        Text(formatTarget((p.dialStart + p.dialEnd) / 2))
                            .font(CoachTokens.mono(56, weight: .bold))
                            .tracking(-2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, CoachTokens.purple],
                                    startPoint: .top, endPoint: .bottom))
                        Text(countdownLabel(to: (p.dialStart + p.dialEnd) / 2))
                            .font(CoachTokens.mono(11))
                            .foregroundStyle(CoachTokens.textDim)
                    }
                }
                .padding(.top, 30)
            }
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("Un paso pequeño\npara cortar la racha")
                .font(CoachTokens.sans(19, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("40 min antes que ayer. Suficiente para que mañana notes la diferencia.")
                .font(CoachTokens.sans(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(CoachTokens.textDim)
                .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private var preparationList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREPARACIÓN SUGERIDA")
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            ForEach(steps, id: \.time) { step in
                HStack(spacing: 10) {
                    Text(step.time)
                        .font(CoachTokens.mono(13, weight: .semibold))
                        .foregroundStyle(step.color)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.label)
                            .font(CoachTokens.sans(13, weight: .medium))
                            .foregroundStyle(.white)
                        Text(step.detail)
                            .font(CoachTokens.sans(11))
                            .foregroundStyle(CoachTokens.textDim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    step.highlight
                    ? AnyView(LinearGradient(colors: [CoachTokens.purple.opacity(0.18), CoachTokens.card],
                                              startPoint: .leading, endPoint: .trailing))
                    : AnyView(CoachTokens.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(step.highlight ? CoachTokens.purple.opacity(0.35) : CoachTokens.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private var bottomCTA: some View {
        HStack {
            Button { activateReminder() } label: {
                Text("Activar recordatorio")
                    .font(CoachTokens.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(
                        colors: [CoachTokens.purple, CoachTokens.purpleDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
                Color(hex: "1E1E3C").opacity(0.72)
            })
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    // MARK: Data

    private var steps: [Step] {
        [
            .init(time: "00:30", label: "Atenúa luces", detail: "Pantallas en modo cálido",
                  color: CoachTokens.yellow, highlight: false),
            .init(time: "01:00", label: "Sin cafeína", detail: "Última taza 8h antes",
                  color: CoachTokens.yellow, highlight: false),
            .init(time: "01:20", label: "Rutina corta", detail: "Cepíllate, lee 5 min",
                  color: CoachTokens.purple, highlight: false),
            .init(time: "01:30", label: "Luces apagadas", detail: "Objetivo",
                  color: CoachTokens.purple, highlight: true),
        ]
    }

    private struct Step {
        let time: String
        let label: String
        let detail: String
        let color: Color
        let highlight: Bool
    }

    // MARK: Helpers

    private func formatTarget(_ h: Double) -> String {
        let hh = Int(h) % 24, mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    private func countdownLabel(to hour: Double) -> String {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowHours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        var diff = hour - nowHours
        if diff < 0 { diff += 24 }
        let h = Int(diff)
        let m = Int((diff - Double(h)) * 60)
        return "en \(h)h \(m)min"
    }

    private func activateReminder() {
        // Wire to existing BackgroundTaskManager / notification scheduler.
        // Out of scope for the UI plan — leave a single call site.
        // Expected integration: BackgroundTaskManager.scheduleBedtimeReminder(adapter.proposal?.dialStart)
    }
}

#Preview {
    CoachPlanView()
        .environment(SpiralStore.preview)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 18.2: Build + suggest commit** → `feat(coach): add CoachPlanView sub-screen`

---

## Task 19: CoachPatternsView (sub-screen)

**Files:**
- Create: `spiral journey project/Views/Coach/Screens/CoachPatternsView.swift`

Heatmap 7×4, correlation card (with/without training), insights list.

- [ ] **Step 19.1: Write CoachPatternsView**

```swift
import SwiftUI
import SpiralKit

struct CoachPatternsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.blue.opacity(0.18), .clear],
                           center: UnitPoint(x: -0.1, y: -0.05),
                           startRadius: 20, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    heatmapCard
                    correlationCard
                    insightsList
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachTokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ÚLTIMOS 30 DÍAS")
                    .font(CoachTokens.mono(10))
                    .foregroundStyle(CoachTokens.textDim)
                    .tracking(1)
                Text("Patrones")
                    .font(CoachTokens.sans(22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MAPA DE CALOR · HORA DE ACOSTARSE")
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.blue)
                .tracking(1)
            Text("Los viernes y sábados duermes 1h 47m más tarde")
                .font(CoachTokens.sans(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 4)

            HStack(spacing: 3) {
                ForEach(Array(["L","M","X","J","V","S","D"].enumerated()), id: \.offset) { di, d in
                    VStack(spacing: 2) {
                        Text(d).font(CoachTokens.mono(9)).foregroundStyle(CoachTokens.textDim)
                        ForEach(0..<4, id: \.self) { wi in
                            let late = (di == 4 || di == 5)
                            let v = late
                                ? 0.7 + Double((wi * 17) % 30) / 100.0
                                : Double((wi * 23) % 55) / 100.0
                            Rectangle()
                                .fill(late
                                      ? CoachTokens.yellow.opacity(v)
                                      : CoachTokens.purple.opacity(v))
                                .frame(height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)

            HStack {
                Text("00:30")
                Spacer()
                Text("→ tarde →")
                Spacer()
                Text("03:30")
            }
            .font(CoachTokens.mono(9))
            .foregroundStyle(CoachTokens.textFaint)
            .padding(.top, 8)
        }
        .padding(16)
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var correlationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CORRELACIÓN DETECTADA")
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.purple)
                .tracking(1)
            Text("Cuando entrenas, duermes 38 min antes")
                .font(CoachTokens.sans(15, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                correlationColumn(label: "CON ENTRENO", value: "00:52",
                                  color: CoachTokens.green, barWidth: 1.0)
                correlationColumn(label: "SIN ENTRENO", value: "01:30",
                                  color: CoachTokens.yellow, barWidth: 0.75)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func correlationColumn(label: String, value: String, color: Color, barWidth: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(CoachTokens.mono(9))
                .foregroundStyle(CoachTokens.textDim)
            Text(value)
                .font(CoachTokens.mono(22, weight: .bold))
                .foregroundStyle(color)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.6))
                    .frame(width: g.size.width * barWidth, height: 5)
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insightsList: some View {
        VStack(spacing: 0) {
            insightRow(icon: "flame", label: "Racha mejor hábito",
                       value: "12 días", sub: "Noviembre", color: CoachTokens.yellow, isFirst: true)
            insightRow(icon: "moon.stars", label: "Mejor día de la semana",
                       value: "Martes", sub: "Score 78", color: CoachTokens.purple)
            insightRow(icon: "chart.line.uptrend.xyaxis", label: "Tendencia 30d",
                       value: "+4 pts", sub: "Mejorando", color: CoachTokens.green)
            insightRow(icon: "clock", label: "Hora ideal de acostarse",
                       value: "01:18", sub: "Según cronotipo", color: CoachTokens.blue)
        }
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func insightRow(icon: String, label: String, value: String, sub: String,
                             color: Color, isFirst: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13))
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(CoachTokens.sans(13, weight: .medium)).foregroundStyle(.white)
                Text(sub).font(CoachTokens.sans(10)).foregroundStyle(CoachTokens.textDim)
            }
            Spacer()
            Text(value).font(CoachTokens.mono(15, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(CoachTokens.border).frame(height: 1)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoachPatternsView()
            .environment(SpiralStore.preview)
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 19.2: Build + suggest commit** → `feat(coach): add CoachPatternsView sub-screen`

---

## Task 20: Restyle CoachChatView

**Files:**
- Modify: `spiral journey project/Views/Coach/CoachChatView.swift`

Only restyles visuals. Keep the existing `CoachProviderFactory`, message persistence, download flow intact.

- [ ] **Step 20.1: Read current file**

Read: `spiral journey project/Views/Coach/CoachChatView.swift:1-472`

Identify the struct names for:
- Message bubbles (user/bot): probably `ChatBubble` or inline code
- Header bar
- Input bar with mic/send button

- [ ] **Step 20.2: Apply restyle diffs**

Wrap the outer root in a `ZStack` with the ambient radial gradient:
```swift
ZStack(alignment: .bottom) {
    CoachTokens.bg.ignoresSafeArea()
    RadialGradient(colors: [CoachTokens.purple.opacity(0.22), .clear],
                   center: UnitPoint(x: 1.1, y: -0.1),
                   startRadius: 20, endRadius: 240)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    /* existing content */
}
```

Replace the header with:
```swift
HStack(spacing: 12) {
    Button { dismiss() } label: {
        Image(systemName: "chevron.left")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(CoachTokens.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
            SparkSpiralView(size: 18, turns: 3, color: CoachTokens.purple, lineWidth: 1.6)
            Text("Coach").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Circle().fill(CoachTokens.green).frame(width: 6, height: 6)
                .shadow(color: CoachTokens.green, radius: 3)
        }
        Text("EN LÍNEA")
            .font(CoachTokens.mono(10))
            .foregroundStyle(CoachTokens.textDim)
            .tracking(0.5)
    }
    Spacer()
}
.padding(.horizontal, 20)
.padding(.vertical, 10)
```

Update bubble styles — user bubbles get purple solid + `[16,16,4,16]` radii; bot bubbles get `CoachTokens.card` + border + `[4,16,16,16]` and an avatar:
```swift
// Avatar (bot only)
ZStack {
    Circle().fill(LinearGradient(
        colors: [CoachTokens.purple, CoachTokens.purpleDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing))
    SparkSpiralView(size: 18, turns: 3, color: .white, lineWidth: 1.5)
}
.frame(width: 32, height: 32)
.shadow(color: CoachTokens.purple.opacity(0.35), radius: 5)
```

Update input bar with mic icon (keep send):
```swift
HStack(spacing: 8) {
    Button { /* attach */ } label: {
        Image(systemName: "plus").font(.system(size: 16))
            .foregroundStyle(CoachTokens.textDim)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.06))
            .clipShape(Circle())
    }
    TextField("Escribe al Coach…", text: $inputText, axis: .vertical)
        .textFieldStyle(.plain)
        .font(CoachTokens.sans(13))
        .foregroundStyle(.white)
    Button { onSend() } label: {
        Image(systemName: inputText.isEmpty ? "mic.fill" : "arrow.up")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(LinearGradient(
                colors: [CoachTokens.purple, CoachTokens.purpleDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
    }
}
.padding(6)
.background(
    ZStack {
        RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
        Color(hex: "1E1E3C").opacity(0.72)
    })
.overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.12), lineWidth: 1))
.clipShape(RoundedRectangle(cornerRadius: 28))
.padding(.horizontal, 12)
.padding(.bottom, 16)
```

**Keep unchanged:** `@Environment(SpiralStore.self) store`, `CoachProviderFactory.makeProvider()`, `store.chatHistory` persistence, download progress UI, the iOS 26 Foundation Models path.

- [ ] **Step 20.3: Build + manual visual check**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

Launch → Coach tab → tap "Pregúntame…" in dock → verify new header with avatar spark + green dot + restyled bubbles + floating input bar.

- [ ] **Step 20.4: Suggest commit** → `feat(coach): restyle chat view with handoff design`

---

## Task 21: Localization keys

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

Add the following keys. The existing xcstrings has 8 locales: `ar`, `ca`, `de`, `en`, `es`, `fr`, `ja`, `zh-Hans`. Copy already appears in Spanish in the plan; translate the 7 others. If this is a large ask, provide English as the source and set others as fallback; a later pass will translate.

- [ ] **Step 21.1: List keys to add**

```
coach.home.feed.divider                      = "LA HISTORIA DE HOY"
coach.home.hero.tonight                       = "ESTA NOCHE"
coach.home.hero.score.label                   = "SCORE"
coach.home.hero.weekSummary                   = "7 NOCHES · %@ MEDIA"
coach.home.greeting.morning                   = "Buenos días"
coach.home.greeting.afternoon                 = "Buenas tardes"
coach.home.greeting.evening                   = "Buenas noches"

coach.home.bento.duration.title               = "DURACIÓN"
coach.home.bento.consistency.title            = "CONSISTENCIA"
coach.home.bento.consistency.of100            = "/100 · %@"
coach.home.bento.consistency.irregular        = "irregular"
coach.home.bento.consistency.variable         = "variable"
coach.home.bento.consistency.consistent       = "consistente"
coach.home.bento.consistency.solid            = "sólido"
coach.home.bento.patterns.title               = "PATRONES"
coach.home.bento.patterns.stable              = "estable"
coach.home.bento.patterns.noChange            = "sin cambios"
coach.home.bento.patterns.thisWeek            = "esta semana"
coach.home.bento.habit.title                  = "HÁBITO"
coach.home.bento.habit.consecutiveDays        = "días seguidos"

coach.home.story.change.tag                   = "LO QUE CAMBIÓ"
coach.home.story.change.bedtimeLabel          = "HORA DE ACOSTARSE"
coach.home.story.propose.tag                  = "LO QUE TE PROPONGO"
coach.home.story.propose.optimalWindow        = "VENTANA ÓPTIMA"
coach.home.story.propose.chronotypeLabel      = "Cronotipo: %@"
coach.home.story.propose.remindMe             = "Recuérdamelo"
coach.home.story.propose.adjust               = "Ajustar"
coach.home.story.learn.tag                    = "APRENDE · 3 MIN"
coach.home.story.learn.subtitle               = "Lectura breve"

coach.dock.askPlaceholder                     = "Pregúntame…"
coach.dock.tab.spiral                         = "Espiral"
coach.dock.tab.trends                         = "Tendencias"
coach.dock.tab.settings                       = "Ajustes"

coach.plan.header                             = "PLAN · ESTA NOCHE"
coach.plan.bedtimeAt                          = "ACUÉSTATE A LAS"
coach.plan.countdown                          = "en %dh %dmin"
coach.plan.headline                           = "Un paso pequeño\npara cortar la racha"
coach.plan.description                        = "40 min antes que ayer. Suficiente para que mañana notes la diferencia."
coach.plan.preparation                        = "PREPARACIÓN SUGERIDA"
coach.plan.cta.enableReminder                 = "Activar recordatorio"

coach.patterns.header                         = "ÚLTIMOS 30 DÍAS"
coach.patterns.title                          = "Patrones"
coach.patterns.heatmap.label                  = "MAPA DE CALOR · HORA DE ACOSTARSE"
coach.patterns.correlation.tag                = "CORRELACIÓN DETECTADA"
coach.patterns.correlation.withTraining       = "CON ENTRENO"
coach.patterns.correlation.withoutTraining    = "SIN ENTRENO"

coach.chat.status.online                      = "EN LÍNEA"
coach.chat.input.placeholder                  = "Escribe al Coach…"
```

- [ ] **Step 21.2: Read current xcstrings format**

Read: `spiral journey project/Localizable.xcstrings:1-40`

Confirm JSON structure (typical: `{"strings": {"key": {"localizations": {"es": {"stringUnit": {"state": "translated", "value": "…"}}}}}}`).

- [ ] **Step 21.3: Append keys**

Add each key with Spanish values as in step 21.1. For other locales:
- `en`: write in English (e.g., `"coach.home.feed.divider" = "TODAY'S STORY"`).
- `ca`, `de`, `fr`, `ja`, `zh-Hans`, `ar`: add with `"state": "needs_review"` and `"value"` = the English text as placeholder. A follow-up translation pass is out of scope for this plan.

- [ ] **Step 21.4: Replace hardcoded strings in the Coach views**

Grep for hardcoded Spanish strings in the 14 Coach-related files:
```
grep -rn '"ESTA NOCHE"\|"SCORE"\|"LA HISTORIA DE HOY"\|"Pregúntame…"' "spiral journey project/Views/Coach/"
```

Replace each with `String(localized: "coach.…", bundle: bundle)`.

For interpolated strings (e.g. `"7 NOCHES · +0.1h MEDIA"`), use:
```swift
String(format: String(localized: "coach.home.hero.weekSummary", bundle: bundle), "-1.2h")
```

- [ ] **Step 21.5: Build + run**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet`

Launch simulator with Spanish locale → verify strings render. Switch to English in Settings → verify English fallback works.

- [ ] **Step 21.6: Suggest commit** → `feat(coach): localize 35+ new strings`

---

## Task 22: Cleanup — remove honeycomb files

**Files:**
- Delete: `spiral journey project/Views/Coach/CoachBubbleViews.swift`
- Delete: `spiral journey project/Views/Coach/CoachBubbleEngine.swift`

Only after manual verification that CoachHomeView + adapter cover all the data previously surfaced by the honeycomb.

- [ ] **Step 22.1: Verify no remaining references**

```
grep -rn "CoachHoneycombEngine\|HoneycombGridView\|BubbleKind\|HoneycombIcon" "spiral journey project/" "Spiral Watch App Watch App/"
```

Expected: matches only inside the two files about to be deleted. If anything else references them, update or remove the reference first.

- [ ] **Step 22.2: Delete both files**

```
rm "spiral journey project/Views/Coach/CoachBubbleViews.swift"
rm "spiral journey project/Views/Coach/CoachBubbleEngine.swift"
```

Remove their entries from `spiral journey project.xcodeproj/project.pbxproj` (Xcode should do this automatically if you delete through the IDE).

- [ ] **Step 22.3: Full build + run**

```
xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A" -quiet
xcodebuild build -scheme "spiral journey project" -destination "platform=macOS" -quiet
xcodebuild build -scheme "Spiral Watch App Watch App" -destination generic/platform=watchOS -quiet
```

All three must succeed. Honeycomb was iOS-only but Watch and macOS both share code that sometimes references the engine indirectly.

- [ ] **Step 22.4: Suggest commit** → `chore(coach): remove honeycomb engine + views`

---

## Verification checklist (before declaring the redesign done)

- [ ] Coach tab boots into CoachHomeView on cold start with data loaded.
- [ ] Cold start with empty store shows a graceful placeholder (test via `store.records.isEmpty`). The current CoachTab had an `emptyState`; port it into CoachHomeView if missing.
- [ ] Score 55 → hero accent purple; score 82 → hero accent green (GoodNight variant renders via the same view).
- [ ] Tapping "Pregúntame…" opens CoachChatView as sheet.
- [ ] Tapping PATRONES card pushes CoachPatternsView.
- [ ] Tapping "Recuérdamelo" presents CoachPlanView as sheet.
- [ ] CoachDock visible on Coach tab, hidden on other tabs.
- [ ] System tab bar hidden on Coach tab, visible on the other three.
- [ ] Dark mode only (light mode toggled → still dark).
- [ ] Spanish, English, and one other locale (e.g. French) render without layout overflow.
- [ ] All 3 platforms build: iOS, macOS, watchOS.
- [ ] Cursor stability intact (no regression in SpiralTab).
- [ ] No force unwraps on optional store properties (`analysis.enhancedCoach?`, `chronotypeResult?`).
- [ ] No `print()` outside `#if DEBUG` in new files.

---

## GoodNight variant (no new task)

The design includes a score-≥70 "Noche buena" variant with a green palette. This is achieved automatically by:
- Hero accent via `CoachTokens.accent(forScore:)` returning green.
- Story cards unchanged (same purple propose, same blue learn), since the GoodNight screen still uses them in the handoff.

The "LOGRO DESBLOQUEADO · Racha de 12 noches" card in the handoff's GoodNight screen is out of scope for this plan — it can be added as an extra StoryCard case later, gated on `streak.currentStreak >= 12`.
