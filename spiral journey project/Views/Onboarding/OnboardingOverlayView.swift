import SwiftUI

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable {
    case welcome    // Spotlight: spiral area
    case sleepLog   // Spotlight: moon button
    case cursor     // Spotlight: spiral (drag gesture)
    case events     // Spotlight: (+) event button in cursor bar
    case tabs       // Spotlight: tab bar
}

// MARK: - Main overlay view

struct OnboardingOverlayView: View {

    let frames: OnboardingFrames

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle)  private var bundle

    @State private var step: OnboardingStep = .welcome
    @State private var tooltipVisible = true
    @State private var pulseScale: CGFloat = 1.0

    private var isLast: Bool { step == OnboardingStep.allCases.last }
    private var stepNumber: Int { step.rawValue + 1 }
    private var totalSteps: Int { OnboardingStep.allCases.count }

    // MARK: - Highlight geometry derived from real frames

    private struct Highlight {
        let rect: CGRect
        let cornerRadius: CGFloat
        /// Y coordinate the tooltip should anchor to (top or bottom of highlight)
        let tooltipAnchorY: CGFloat
        let tooltipBelow: Bool
    }

    private func highlight(for step: OnboardingStep, screenSize: CGSize) -> Highlight {
        switch step {
        case .welcome:
            let r = frames.spiralArea.isEmpty
                ? CGRect(x: 16, y: screenSize.height * 0.18, width: screenSize.width - 32, height: screenSize.height * 0.52)
                : frames.spiralArea.insetBy(dx: 0, dy: 4)
            return Highlight(rect: r, cornerRadius: 20,
                             tooltipAnchorY: r.midY,
                             tooltipBelow: true)

        case .sleepLog:
            let raw = frames.moonButton.isEmpty
                ? CGRect(x: screenSize.width - 80, y: 80, width: 64, height: 64)
                : frames.moonButton.insetBy(dx: -8, dy: -8)
            // Force square so the highlight is a perfect circle
            let side = max(raw.width, raw.height)
            let r = CGRect(x: raw.midX - side / 2, y: raw.midY - side / 2, width: side, height: side)
            return Highlight(rect: r, cornerRadius: side / 2,
                             tooltipAnchorY: r.maxY + 4,
                             tooltipBelow: true)

        case .cursor:
            let spiral = frames.spiralArea.isEmpty
                ? CGRect(x: 16, y: screenSize.height * 0.18, width: screenSize.width - 32, height: screenSize.height * 0.52)
                : frames.spiralArea
            let d = min(spiral.width, spiral.height) - 48
            let r = CGRect(x: spiral.midX - d / 2, y: spiral.midY - d / 2, width: d, height: d)
            return Highlight(rect: r, cornerRadius: d / 2,
                             tooltipAnchorY: spiral.maxY - 4,
                             tooltipBelow: false)

        case .events:
            let r = frames.eventsBtn.isEmpty
                ? CGRect(x: screenSize.width - 64, y: screenSize.height * 0.76, width: 48, height: 32)
                : frames.eventsBtn.insetBy(dx: -10, dy: -8)
            return Highlight(rect: r, cornerRadius: 10,
                             tooltipAnchorY: r.maxY + 4,
                             tooltipBelow: true)

        case .tabs:
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let r: CGRect
            if !frames.tabBar.isEmpty {
                r = frames.tabBar
            } else if isPad {
                // On iPad, TabView renders tabs at the top
                r = CGRect(x: 0, y: 0, width: screenSize.width, height: 70)
            } else {
                r = CGRect(x: 0, y: screenSize.height - 83, width: screenSize.width, height: 83)
            }
            let tooltipBelow = isPad && frames.tabBar.isEmpty ? true : false
            let anchorY = tooltipBelow ? r.maxY + 8 : r.minY - 8
            return Highlight(rect: r, cornerRadius: 0,
                             tooltipAnchorY: anchorY,
                             tooltipBelow: tooltipBelow)
        }
    }

    // MARK: - Step content

    private struct StepContent {
        let titleKey: String
        let messageKey: String
        let icon: String
        let arrowDirection: ArrowDirection
        enum ArrowDirection { case up, down, none }
    }

    private var stepContent: StepContent {
        switch step {
        case .welcome:
            return StepContent(titleKey: "onboarding.welcome.title",
                               messageKey: "onboarding.welcome.message",
                               icon: "sparkles", arrowDirection: .none)
        case .sleepLog:
            return StepContent(titleKey: "onboarding.sleepLog.title",
                               messageKey: "onboarding.sleepLog.message",
                               icon: "moon.fill", arrowDirection: .up)
        case .cursor:
            return StepContent(titleKey: "onboarding.cursor.title",
                               messageKey: "onboarding.cursor.message",
                               icon: "hand.draw", arrowDirection: .down)
        case .events:
            return StepContent(titleKey: "onboarding.events.title",
                               messageKey: "onboarding.events.message",
                               icon: "plus.circle", arrowDirection: .up)
        case .tabs:
            return StepContent(titleKey: "onboarding.tabs.title",
                               messageKey: "onboarding.tabs.message",
                               icon: "rectangle.3.group", arrowDirection: .down)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let hl = highlight(for: step, screenSize: geo.size)
            let content = stepContent

            ZStack {
                // 1. Dimming layer with spotlight cutout
                Color.black.opacity(0.65)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: hl.cornerRadius)
                            .frame(width: hl.rect.width, height: hl.rect.height)
                            .position(x: hl.rect.midX, y: hl.rect.midY)
                    }
                    .ignoresSafeArea()
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)

                // 2. Highlight glow border
                RoundedRectangle(cornerRadius: hl.cornerRadius)
                    .stroke(SpiralColors.accent.opacity(0.6), lineWidth: 1.5)
                    .frame(width: hl.rect.width, height: hl.rect.height)
                    .scaleEffect(pulseScale)
                    .position(x: hl.rect.midX, y: hl.rect.midY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)

                // 3. Tooltip bubble
                tooltipBubble(hl: hl, content: content, geo: geo)
                    .opacity(tooltipVisible ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { }   // Swallow taps on dimmed area
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulseScale = 1.06
            }
        }
    }

    // MARK: - Tooltip bubble

    @ViewBuilder
    private func tooltipBubble(hl: Highlight, content: StepContent, geo: GeometryProxy) -> some View {
        let tooltipWidth: CGFloat = min(geo.size.width - 48, 320)
        let bubbleH: CGFloat = 155
        let arrowDir = content.arrowDirection
        let anchorY  = hl.tooltipAnchorY

        // Clamp tooltip Y so it stays within screen bounds with 16pt margin
        let rawY = hl.tooltipBelow
            ? anchorY + bubbleH / 2 + (arrowDir == .none ? 0 : 8)
            : anchorY - bubbleH / 2 - (arrowDir == .none ? 0 : 8)
        let tooltipY = rawY.clamped(to: (bubbleH / 2 + 16)...(geo.size.height - bubbleH / 2 - 16))

        VStack(spacing: 0) {
            // Arrow pointing down (tooltip is above the highlight)
            if arrowDir == .down {
                Triangle()
                    .fill(SpiralColors.accent.opacity(0.18))
                    .frame(width: 16, height: 8)
            }

            // Bubble card
            VStack(alignment: .leading, spacing: 10) {
                // Step indicator
                Text(String(format: String(localized: "onboarding.stepIndicator", bundle: bundle),
                            stepNumber, totalSteps))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)

                // Icon + title
                HStack(spacing: 8) {
                    Image(systemName: content.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(SpiralColors.accent)
                    Text(NSLocalizedString(content.titleKey, bundle: bundle, comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                }

                // Message
                Text(NSLocalizedString(content.messageKey, bundle: bundle, comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(SpiralColors.text.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                // Navigation row
                HStack {
                    Button { dismiss() } label: {
                        Text(String(localized: "onboarding.skip", bundle: bundle))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button { advance() } label: {
                        Text(isLast
                             ? String(localized: "onboarding.done", bundle: bundle)
                             : String(localized: "onboarding.next", bundle: bundle))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(SpiralColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: tooltipWidth, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16).fill(SpiralColors.accent.opacity(0.05))
                    RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.accent.opacity(0.2), lineWidth: 0.8)
                }
            )

            // Arrow pointing up (tooltip is below the highlight)
            if arrowDir == .up {
                Triangle()
                    .rotation(Angle(degrees: 180))
                    .fill(SpiralColors.accent.opacity(0.18))
                    .frame(width: 16, height: 8)
            }
        }
        .frame(width: tooltipWidth)
        .position(x: geo.size.width / 2, y: tooltipY)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)
    }

    // MARK: - Navigation

    private func advance() {
        let steps = OnboardingStep.allCases
        if let idx = steps.firstIndex(of: step), idx + 1 < steps.count {
            withAnimation(.easeOut(duration: 0.15)) { tooltipVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    step = steps[idx + 1]
                    tooltipVisible = true
                }
            }
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            store.hasCompletedOnboarding = true
        }
    }
}

// MARK: - Helper shapes & extensions

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Masks the view with an inverted (cutout) version of the provided mask view.
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask(
            Rectangle()
                .ignoresSafeArea()
                .overlay { mask().blendMode(.destinationOut) }
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
