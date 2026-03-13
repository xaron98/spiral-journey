import SwiftUI
import SpiralKit

/// Event logging panel — records zeitgeber events at a given spiral position.
struct EventPanelView: View {

    let events: [CircadianEvent]
    let cursorAbsoluteHour: Double
    let onAdd: (CircadianEvent) -> Void
    let onRemove: (UUID) -> Void
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(title: String(localized: "events.title", bundle: bundle))

            Text(String(format: String(localized: "events.logAt", bundle: bundle), SleepStatistics.formatHour(cursorAbsoluteHour.truncatingRemainder(dividingBy: 24))))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)

            // Event type buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(EventType.allCases, id: \.self) { type in
                    EventTypeButton(type: type) {
                        let event = CircadianEvent(
                            type: type,
                            absoluteHour: cursorAbsoluteHour,
                            timestamp: Date()
                        )
                        onAdd(event)
                    }
                }
            }

            // Logged events list
            if !events.isEmpty {
                Divider().background(SpiralColors.border)
                ForEach(events) { event in
                    HStack(spacing: 6) {
                        Image(systemName: event.type.sfSymbol)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: event.type.hexColor))
                            .frame(width: 14)
                        Text(event.type.label)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                        Spacer()
                        Text(SleepStatistics.formatHour(event.absoluteHour.truncatingRemainder(dividingBy: 24)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)

                        // PRC shift
                        let shift = PhaseResponse.models[event.type]?.fn(event.absoluteHour.truncatingRemainder(dividingBy: 24)) ?? 0
                        if abs(shift) > 0.01 {
                            Text(String(format: "%+.1fh", shift))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(shift > 0 ? SpiralColors.good : SpiralColors.poor)
                        }

                        Button {
                            onRemove(event.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundStyle(SpiralColors.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .panelStyle()
    }
}

private struct EventTypeButton: View {
    let type: EventType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: type.hexColor))
                Text(type.label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(SpiralColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: type.hexColor).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
