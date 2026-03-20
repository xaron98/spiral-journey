import SwiftUI
import SwiftData

/// Weekly mini-questionnaire for scientific validation (PSQI/ESS abbreviated).
///
/// 5 questions, ~1 minute to complete. Persisted as `SDQuestionnaireResponse` in SwiftData.
struct WeeklyQuestionnaireView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    /// Callback fired after the user submits or skips.
    var onComplete: () -> Void = {}

    // MARK: - State

    @State private var sleepQuality: Double = 3
    @State private var daytimeSleepiness: Double = 3
    @State private var patternAccuracy: String = "yes"
    @State private var weekendDifference: Bool = false
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "list.clipboard")
                            .font(.title)
                            .foregroundStyle(SpiralColors.accent)
                        Text(loc("questionnaire.title"))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("questionnaire.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(SpiralColors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Q1: Sleep quality (PSQI abbreviated)
                    questionCard {
                        Text(loc("questionnaire.q1"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        sliderRow(value: $sleepQuality, range: 1...5, step: 1,
                                  lowLabel: loc("questionnaire.q1.low"),
                                  highLabel: loc("questionnaire.q1.high"))
                    }

                    // Q2: Daytime sleepiness (ESS abbreviated)
                    questionCard {
                        Text(loc("questionnaire.q2"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        sliderRow(value: $daytimeSleepiness, range: 1...5, step: 1,
                                  lowLabel: loc("questionnaire.q2.low"),
                                  highLabel: loc("questionnaire.q2.high"))
                    }

                    // Q3: Pattern accuracy
                    questionCard {
                        Text(loc("questionnaire.q3"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        HStack(spacing: 8) {
                            ForEach(["yes", "partially", "no"], id: \.self) { option in
                                Button {
                                    patternAccuracy = option
                                } label: {
                                    Text(loc("questionnaire.q3.\(option)"))
                                        .font(.caption.weight(.medium).monospaced())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(patternAccuracy == option
                                                     ? SpiralColors.accent.opacity(0.2)
                                                     : SpiralColors.subtle.opacity(0.15))
                                        .foregroundStyle(patternAccuracy == option
                                                         ? SpiralColors.accent
                                                         : SpiralColors.muted)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Q4: Weekend difference
                    questionCard {
                        Toggle(isOn: $weekendDifference) {
                            Text(loc("questionnaire.q4"))
                                .font(.footnote.monospaced())
                                .foregroundStyle(SpiralColors.text)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                    }

                    // Q5: Notes (optional)
                    questionCard {
                        Text(loc("questionnaire.q5"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        TextField(loc("questionnaire.q5.placeholder"), text: $notes, axis: .vertical)
                            .font(.footnote.monospaced())
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(SpiralColors.subtle.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Submit
                    Button {
                        submit()
                    } label: {
                        Text(loc("questionnaire.submit"))
                            .font(.body.weight(.semibold).monospaced())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SpiralColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        onComplete()
                    } label: {
                        Text(loc("questionnaire.skip"))
                            .font(.footnote.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func questionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .panelStyle()
    }

    @ViewBuilder
    private func sliderRow(value: Binding<Double>, range: ClosedRange<Double>, step: Double, lowLabel: String, highLabel: String) -> some View {
        VStack(spacing: 4) {
            Slider(value: value, in: range, step: step)
                .tint(SpiralColors.accent)
            HStack {
                Text(lowLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(String(format: "%.0f", value.wrappedValue))
                    .font(.footnote.weight(.bold).monospaced())
                    .foregroundStyle(SpiralColors.accent)
                Spacer()
                Text(highLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
            }
        }
    }

    // MARK: - Logic

    private func submit() {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        let response = SDQuestionnaireResponse(
            weekDate: weekStart,
            sleepQuality: Int(sleepQuality),
            daytimeSleepiness: Int(daytimeSleepiness),
            patternAccuracy: patternAccuracy,
            weekendDifference: weekendDifference,
            notes: notes.isEmpty ? nil : notes,
            completedAt: Date()
        )

        modelContext.insert(response)
        try? modelContext.save()

        dismiss()
        onComplete()
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Availability Check

extension WeeklyQuestionnaireView {

    /// Returns `true` if a weekly questionnaire should be shown (no response this week).
    static func isAvailable(context: ModelContext) -> Bool {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return false
        }

        let descriptor = FetchDescriptor<SDQuestionnaireResponse>(
            predicate: #Predicate<SDQuestionnaireResponse> { response in
                response.weekDate >= weekStart
            }
        )

        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count == 0
    }
}
