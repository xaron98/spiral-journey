import SwiftUI
import SwiftData

/// Sheet for writing or reading dream journal entries.
/// Supports multiple dreams per night.
struct DreamEntrySheet: View {

    let sleepDate: Date
    let sleepTimeRange: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.languageBundle) private var bundle
    @Environment(OnDeviceAIService.self) private var aiService
    @Environment(SpiralStore.self) private var store

    @State private var dreamText: String = ""
    @State private var intensity: Int = 3
    @State private var existingDreams: [SDDreamEntry] = []
    @State private var interpretation: String?
    @State private var isInterpreting = false
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(loc("dream.entry.cancel")) { dismiss() }
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(loc("dream.entry.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Button(loc("dream.entry.save")) {
                    saveDream()
                }
                .foregroundStyle(SpiralColors.accent)
                .disabled(dreamText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Sleep context
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(SpiralColors.accent)
                        Text(sleepTimeRange)
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                    }

                    // Previous dreams for this night
                    if !existingDreams.isEmpty {
                        ForEach(existingDreams) { dream in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dream.text)
                                    .font(.footnote)
                                    .foregroundStyle(SpiralColors.text)
                                HStack {
                                    Text(dream.createdAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(SpiralColors.subtle)
                                    if let i = dream.intensity {
                                        Text(String(repeating: "●", count: i))
                                            .font(.caption2)
                                            .foregroundStyle(SpiralColors.accent)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(SpiralColors.surface)
                            )
                        }

                        Divider().background(SpiralColors.border.opacity(0.3))
                            .padding(.vertical, 4)
                    }

                    // New dream input
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

                    // Interpret button
                    if aiService.isAvailable && !allDreamTexts.isEmpty {
                        Button {
                            if #available(iOS 26, *) {
                                Task { await interpretDream() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isInterpreting {
                                    ProgressView().controlSize(.small).tint(SpiralColors.accent)
                                } else {
                                    Image(systemName: "sparkles").font(.caption)
                                }
                                Text(loc("dream.interpret.button"))
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundStyle(SpiralColors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(SpiralColors.accent.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isInterpreting)
                    }

                    // Interpretation
                    if let interpretation {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles").font(.caption)
                                    .foregroundStyle(SpiralColors.accent)
                                Text(loc("dream.interpret.title"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.subtle)
                                    .textCase(.uppercase)
                            }
                            Text(interpretation)
                                .font(.footnote)
                                .foregroundStyle(SpiralColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(SpiralColors.accent.opacity(0.05))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .task { loadExisting() }
    }

    // MARK: - All dream texts (existing + current input)

    private var allDreamTexts: [String] {
        var texts = existingDreams.map { $0.text }
        let trimmed = dreamText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { texts.append(trimmed) }
        return texts
    }

    // MARK: - AI

    @available(iOS 26, *)
    private func interpretDream() async {
        isInterpreting = true
        defer { isInterpreting = false }

        let allDescriptor = FetchDescriptor<SDDreamEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let otherDreams = (try? modelContext.fetch(allDescriptor))?
            .filter { !Calendar.current.isDate($0.sleepDate, inSameDayAs: sleepDate) }
            .prefix(5)
            .map { $0.text } ?? []

        let result = await aiService.interpretDream(
            dreamText: allDreamTexts.joined(separator: "\n---\n"),
            sleepPhases: sleepTimeRange,
            previousDreams: Array(otherDreams),
            locale: store.language.localeIdentifier
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            interpretation = result
        }
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
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: sleepDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<SDDreamEntry>(
            predicate: #Predicate { $0.sleepDate >= start && $0.sleepDate < end },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        existingDreams = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveDream() {
        let trimmed = dreamText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Always create a new entry (multiple dreams per night)
        let entry = SDDreamEntry(sleepDate: sleepDate, text: trimmed, intensity: intensity)
        modelContext.insert(entry)

        // Reset for next dream
        dreamText = ""
        intensity = 3
        loadExisting()
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
