import SwiftUI
import SpiralKit

/// MEQ-5 chronotype questionnaire shown after the welcome screen.
///
/// 5 paged questions with animated transitions, progress indicator,
/// and a result screen showing the user's chronotype classification.
struct ChronotypeQuestionnaireView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    /// Called when the user finishes (taps Continue on result screen).
    var onComplete: () -> Void

    @State private var currentQuestion = 0
    @State private var answers: [Int] = Array(repeating: 0, count: 5)
    @State private var showResult = false
    @State private var result: ChronotypeResult?

    var body: some View {
        ZStack {
            SpiralColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Progress bar ──────────────────────────────────────
                if !showResult {
                    progressBar
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer()

                if showResult, let result {
                    resultView(result)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    questionView(index: currentQuestion)
                        .id(currentQuestion) // Forces view identity change for transition
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }

                Spacer()

                // ── Navigation ────────────────────────────────────────
                if !showResult {
                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentQuestion)
        .animation(.easeInOut(duration: 0.4), value: showResult)
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= currentQuestion ? SpiralColors.accent : SpiralColors.surface)
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Question View

    private func questionView(index: Int) -> some View {
        VStack(spacing: 24) {
            Text(questionTitle(index))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(SpiralColors.muted)
                .textCase(.uppercase)

            Text(questionText(index))
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(SpiralColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(1...5, id: \.self) { option in
                    optionButton(question: index, option: option)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func optionButton(question: Int, option: Int) -> some View {
        let isSelected = answers[question] == option
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                answers[question] = option
            }
        } label: {
            Text(optionText(question: question, option: option))
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : SpiralColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? SpiralColors.accent : SpiralColors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? SpiralColors.accent : SpiralColors.border, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            // Back button
            if currentQuestion > 0 {
                Button {
                    withAnimation { currentQuestion -= 1 }
                } label: {
                    Text(String(localized: "chronotype.back", bundle: bundle))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(SpiralColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(SpiralColors.border, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }

            // Next / Submit
            Button {
                if currentQuestion < 4 {
                    withAnimation { currentQuestion += 1 }
                } else {
                    submitQuestionnaire()
                }
            } label: {
                Text(currentQuestion < 4
                     ? String(localized: "chronotype.next", bundle: bundle)
                     : String(localized: "chronotype.seeResult", bundle: bundle))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(answers[currentQuestion] > 0 ? .black : SpiralColors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(answers[currentQuestion] > 0 ? SpiralColors.accent : SpiralColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(answers[currentQuestion] == 0)
        }
    }

    // MARK: - Result View

    private func resultView(_ result: ChronotypeResult) -> some View {
        VStack(spacing: 20) {
            Text(result.chronotype.emoji)
                .font(.system(size: 64))

            Text(chronotypeLocalizedName(result.chronotype))
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SpiralColors.accent)

            Text(String(
                format: String(localized: "chronotype.result.score", bundle: bundle),
                result.totalScore
            ))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(SpiralColors.muted)

            Text(chronotypeDescription(result.chronotype))
                .font(.system(size: 14))
                .foregroundStyle(SpiralColors.text.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            // Ideal schedule summary
            VStack(spacing: 6) {
                scheduleRow(
                    icon: "moon.fill",
                    label: String(localized: "chronotype.result.idealBed", bundle: bundle),
                    value: formatRange(result.chronotype.idealBedRange)
                )
                scheduleRow(
                    icon: "sun.max.fill",
                    label: String(localized: "chronotype.result.idealWake", bundle: bundle),
                    value: formatRange(result.chronotype.idealWakeRange)
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SpiralColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SpiralColors.border, lineWidth: 0.8)
                    )
            )
            .padding(.horizontal, 32)

            Spacer().frame(height: 8)

            // Continue button
            Button(action: onComplete) {
                Text(String(localized: "chronotype.continue", bundle: bundle))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SpiralColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func scheduleRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(SpiralColors.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
        }
    }

    // MARK: - Actions

    private func submitQuestionnaire() {
        guard let scored = ChronotypeEngine.score(answers: answers) else { return }
        result = scored
        store.chronotypeResult = scored

        // Adjust sleep goal if in generalHealth mode
        if store.sleepGoal.mode == .generalHealth {
            store.sleepGoal = ChronotypeEngine.adjustedSleepGoal(
                base: store.sleepGoal,
                chronotype: scored.chronotype
            )
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            showResult = true
        }
    }

    // MARK: - Helpers

    private func formatRange(_ range: (Double, Double)) -> String {
        "\(formatHour(range.0)) – \(formatHour(range.1))"
    }

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h) % 24
        let minute = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Question Data (Localized)

    private func questionTitle(_ index: Int) -> String {
        String(format: String(localized: "chronotype.questionNumber", bundle: bundle), index + 1)
    }

    private func questionText(_ index: Int) -> String {
        let keys = [
            "chronotype.q1", "chronotype.q2", "chronotype.q3",
            "chronotype.q4", "chronotype.q5"
        ]
        return String(localized: String.LocalizationValue(keys[index]), bundle: bundle)
    }

    private func optionText(question: Int, option: Int) -> String {
        let key = "chronotype.q\(question + 1).o\(option)"
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    private func chronotypeLocalizedName(_ ct: Chronotype) -> String {
        let key = "chronotype.result.\(ct.rawValue)"
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    private func chronotypeDescription(_ ct: Chronotype) -> String {
        let key = "chronotype.result.\(ct.rawValue).desc"
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }
}
