import SwiftUI
import SpiralKit

/// Quick-log circadian events directly from the watch.
struct WatchEventLogView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @State private var lastLogged: EventType? = nil
    @State private var showConfirmation = false

    private var currentHour: Double {
        let cal = Calendar.current
        let now = Date()
        return Double(cal.component(.hour, from: now)) + Double(cal.component(.minute, from: now)) / 60.0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(String(localized: "watch.events.logEvent", bundle: bundle))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SpiralColors.text)

                // 2-column grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(EventType.allCases, id: \.self) { type in
                        eventButton(type)
                    }
                }

                if showConfirmation, let last = lastLogged {
                    Text("✓ \(last.label)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: last.hexColor))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: showConfirmation)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(SpiralColors.bg)
        .navigationTitle(String(localized: "watch.events.title", bundle: bundle))
    }

    private func eventButton(_ type: EventType) -> some View {
        Button {
            let event = CircadianEvent(type: type, absoluteHour: currentHour, timestamp: Date())
            store.logEvent(event)
            lastLogged = type
            withAnimation { showConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showConfirmation = false }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: type.hexColor))
                Text(type.label)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(SpiralColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
