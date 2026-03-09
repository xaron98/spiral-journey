import SwiftUI
import SpiralKit

/// Quick-log circadian events from the watch with 6 SF Symbol buttons.
struct WatchEventLogView: View {

    @Environment(WatchStore.self) private var store
    @State private var lastLogged: EventType? = nil
    @State private var showConfirmation = false

    // Current circadian hour estimate (based on wall clock)
    private var currentCircadianHour: Double {
        let cal = Calendar.current
        let now = Date()
        let hour = Double(cal.component(.hour, from: now))
        let minute = Double(cal.component(.minute, from: now))
        return hour + minute / 60.0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Log Event")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#c8cdd8"))

                // 2×3 grid of event buttons
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EventType.allCases, id: \.self) { eventType in
                        eventButton(eventType)
                    }
                }

                if showConfirmation, let last = lastLogged {
                    Text("✓ \(last.label)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(hex: last.hexColor))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(hex: "#0c0e14"))
        .navigationTitle("Events")
    }

    private func eventButton(_ eventType: EventType) -> some View {
        Button {
            let event = CircadianEvent(
                type: eventType,
                absoluteHour: currentCircadianHour,
                timestamp: Date()
            )
            store.logEvent(event)
            lastLogged = eventType
            withAnimation(.easeIn(duration: 0.2)) { showConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showConfirmation = false }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: eventType.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: eventType.hexColor))
                Text(eventType.label)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color(hex: "#555566"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(hex: "#12151e"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
