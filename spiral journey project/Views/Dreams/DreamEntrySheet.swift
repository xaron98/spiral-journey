import SwiftUI
import SwiftData

/// Sheet for writing or editing a dream journal entry.
struct DreamEntrySheet: View {

    let day: Int
    let sleepTimeRange: String  // e.g. "23:30 – 07:15"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.languageBundle) private var bundle

    @State private var dreamText: String = ""
    @State private var intensity: Int = 3
    @State private var existingEntry: SDDreamEntry?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(loc("dream.entry.cancel")) { dismiss() }
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(loc("dream.entry.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Button(loc("dream.entry.save")) {
                    save()
                    dismiss()
                }
                .foregroundStyle(SpiralColors.accent)
                .disabled(dreamText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Sleep context
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(SpiralColors.accent)
                Text(sleepTimeRange)
                    .font(.footnote.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Text input
            TextField(loc("dream.entry.placeholder"), text: $dreamText, axis: .vertical)
                .focused($isTextFocused)
                .lineLimit(4...12)
                .font(.body)
                .foregroundStyle(SpiralColors.text)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SpiralColors.surface)
                )
                .padding(.horizontal, 20)

            // Intensity
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { level in
                    Button { intensity = level } label: {
                        Circle()
                            .fill(level <= intensity ? SpiralColors.accent : SpiralColors.surface)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(intensityLabel)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .task { loadExisting() }
    }

    // MARK: - Helpers

    private var intensityLabel: String {
        switch intensity {
        case 1: return loc("dream.intensity.vague")
        case 2: return loc("dream.intensity.faint")
        case 3: return loc("dream.intensity.normal")
        case 4: return loc("dream.intensity.vivid")
        case 5: return loc("dream.intensity.lucid")
        default: return ""
        }
    }

    private func loadExisting() {
        let targetDay = day
        let descriptor = FetchDescriptor<SDDreamEntry>(
            predicate: #Predicate { $0.day == targetDay }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existingEntry = existing
            dreamText = existing.text
            intensity = existing.intensity ?? 3
        }
    }

    private func save() {
        let trimmed = dreamText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = existingEntry {
            existing.text = trimmed
            existing.intensity = intensity
        } else {
            let entry = SDDreamEntry(day: day, text: trimmed, intensity: intensity)
            modelContext.insert(entry)
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
