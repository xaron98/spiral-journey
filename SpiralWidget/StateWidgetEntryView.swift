import SwiftUI
import WidgetKit

struct StateWidgetEntryView: View {
    let entry: StateEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    // MARK: - Small (state only)

    private var smallView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(Color(hex: entry.stateColorHex))

            Text(entry.stateLabel)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: entry.stateColorHex))
                .multilineTextAlignment(.center)

            if let bed = entry.predictedBed, let wake = entry.predictedWake {
                Text("\(bed) → \(wake)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium (state + prediction)

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: state
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundStyle(Color(hex: entry.stateColorHex))
                Text(entry.stateLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: entry.stateColorHex))
            }
            .frame(maxWidth: .infinity)

            if entry.hasData {
                // Divider
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Right: prediction
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "widget.tonight", defaultValue: "Tonight"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))

                    if let bed = entry.predictedBed, let wake = entry.predictedWake {
                        Text("\(bed) → \(wake)")
                            .font(.title3.weight(.semibold).monospaced())
                            .foregroundStyle(.white)
                    }

                    if let dur = entry.duration {
                        Text("~\(dur)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
