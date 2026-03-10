import SwiftUI

// MARK: - Anchor frames reported by SpiralTab to the onboarding overlay

struct OnboardingFrames: Equatable {
    var spiralArea: CGRect  = .zero
    var moonButton: CGRect  = .zero
    var cursorBar:  CGRect  = .zero
    var eventsBtn:  CGRect  = .zero
    var tabBar:     CGRect  = .zero
}

// One PreferenceKey that carries all frames at once
struct OnboardingFramesKey: PreferenceKey {
    static let defaultValue = OnboardingFrames()
    static func reduce(value: inout OnboardingFrames, nextValue: () -> OnboardingFrames) {
        let n = nextValue()
        if n.spiralArea != .zero { value.spiralArea = n.spiralArea }
        if n.moonButton != .zero { value.moonButton = n.moonButton }
        if n.cursorBar  != .zero { value.cursorBar  = n.cursorBar  }
        if n.eventsBtn  != .zero { value.eventsBtn  = n.eventsBtn  }
        if n.tabBar     != .zero { value.tabBar     = n.tabBar     }
    }
}

// Convenience modifier
extension View {
    func reportFrame(_ keyPath: WritableKeyPath<OnboardingFrames, CGRect>,
                     in coordinateSpace: CoordinateSpace = .global) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: OnboardingFramesKey.self,
                    value: {
                        var f = OnboardingFrames()
                        f[keyPath: keyPath] = geo.frame(in: coordinateSpace)
                        return f
                    }()
                )
            }
        )
    }
}
