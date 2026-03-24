import SwiftUI
import SpiralKit

/// Quick-log circadian events directly from the watch.
struct WatchEventLogView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @State private var lastLogged: EventType? = nil
    @State private var showConfirmation = false

    private var currentHour: Double {
        // Use cursor position so events land exactly where the spiral dot is.
        // Falls back to wall-clock time if cursor hasn't been initialised yet.
        store.cursorAbsoluteHour > 0 ? store.cursorAbsoluteHour : store.currentAbsoluteHour
    }

    private var app: String { store.appearance }

    var body: some View {
        ZStack {
            SpiralColors.bg(app).ignoresSafeArea()
        ScrollView {
            VStack(spacing: 8) {
                Text(String(localized: "watch.events.logEvent", bundle: bundle))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SpiralColors.text(app))

                // 2-column grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle(String(localized: "watch.events.title", bundle: bundle))
        } // ZStack
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
            VStack(spacing: 4) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: type.hexColor))
                Text(type.label)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(SpiralColors.text(app))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color(hex: type.hexColor).opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
