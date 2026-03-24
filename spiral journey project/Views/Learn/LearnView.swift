import SwiftUI
import SpiralKit

/// Educational section — articles about sleep science with quizzes.
struct LearnView: View {

    @Environment(\.languageBundle) private var bundle
    @Environment(SpiralStore.self) private var store
    @AppStorage("learnReadArticles") private var readArticlesData: Data = Data()

    @State private var articles: [LearnArticle] = []
    @State private var selectedArticle: LearnArticle?

    private var readArticleIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: readArticlesData)) ?? []
    }

    private func markRead(_ id: String) {
        var ids = readArticleIDs
        ids.insert(id)
        readArticlesData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress
            let readCount = articles.filter { readArticleIDs.contains($0.id) }.count
            if !articles.isEmpty {
                HStack {
                    Text(String(localized: "learn.progress", bundle: bundle))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text("\(readCount)/\(articles.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.accent)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SpiralColors.surface)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SpiralColors.accent)
                            .frame(width: geo.size.width * CGFloat(readCount) / CGFloat(max(articles.count, 1)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Article list
            ForEach(articles) { article in
                Button {
                    selectedArticle = article
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: article.icon)
                            .font(.title3)
                            .foregroundStyle(SpiralColors.accent)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SpiralColors.text)
                            Text("\(article.sections.count) " + String(localized: "learn.sections", bundle: bundle) + " · \(article.quiz.count) quiz")
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                        }

                        Spacer()

                        if readArticleIDs.contains(article.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SpiralColors.good)
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(SpiralColors.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .glassPanel()
        .onAppear {
            articles = LearnContentLoader.load(locale: store.language.localeIdentifier)
        }
        .sheet(item: $selectedArticle) { article in
            LearnArticleView(article: article, onComplete: {
                markRead(article.id)
            })
        }
    }
}

/// Full article reader with sections, fun facts, and quiz.
struct LearnArticleView: View {

    let article: LearnArticle
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle
    @State private var showQuiz = false
    @State private var selectedAnswers: [Int: Int] = [:]
    @State private var quizSubmitted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: article.icon)
                            .font(.largeTitle)
                            .foregroundStyle(SpiralColors.accent)
                        Text(article.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .padding(.bottom, 4)

                    // Sections
                    ForEach(Array(article.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.header)
                                .font(.headline)
                                .foregroundStyle(SpiralColors.text)

                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(SpiralColors.text.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)

                            if let fact = section.funFact {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                    Text(fact)
                                        .font(.callout.italic())
                                        .foregroundStyle(SpiralColors.accent)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(SpiralColors.accent.opacity(0.08))
                                )
                            }
                        }
                    }

                    Divider().background(SpiralColors.border)

                    // Quiz section
                    if !article.quiz.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "learn.quiz.title", bundle: bundle))
                                .font(.headline)
                                .foregroundStyle(SpiralColors.text)

                            ForEach(Array(article.quiz.enumerated()), id: \.offset) { qIdx, question in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(question.question)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(SpiralColors.text)

                                    ForEach(Array(question.options.enumerated()), id: \.offset) { oIdx, option in
                                        Button {
                                            if !quizSubmitted {
                                                selectedAnswers[qIdx] = oIdx
                                            }
                                        } label: {
                                            HStack {
                                                Text(option)
                                                    .font(.subheadline)
                                                    .foregroundStyle(SpiralColors.text)
                                                Spacer()
                                                if quizSubmitted {
                                                    if oIdx == question.correct {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(SpiralColors.good)
                                                    } else if selectedAnswers[qIdx] == oIdx {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .foregroundStyle(SpiralColors.poor)
                                                    }
                                                } else if selectedAnswers[qIdx] == oIdx {
                                                    Image(systemName: "circle.fill")
                                                        .foregroundStyle(SpiralColors.accent)
                                                        .font(.caption2)
                                                }
                                            }
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(optionBackground(qIdx: qIdx, oIdx: oIdx, correct: question.correct))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !quizSubmitted {
                                Button {
                                    quizSubmitted = true
                                    // If all answered, mark complete
                                    if selectedAnswers.count == article.quiz.count {
                                        onComplete()
                                    }
                                } label: {
                                    Text(String(localized: "learn.quiz.submit", bundle: bundle))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedAnswers.count == article.quiz.count ? SpiralColors.accent : SpiralColors.muted)
                                        )
                                }
                                .disabled(selectedAnswers.count < article.quiz.count)
                            } else {
                                let correctCount = article.quiz.enumerated().filter { selectedAnswers[$0.offset] == $0.element.correct }.count
                                Text("\(correctCount)/\(article.quiz.count) " + String(localized: "learn.quiz.correct", bundle: bundle))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(correctCount == article.quiz.count ? SpiralColors.good : SpiralColors.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private func optionBackground(qIdx: Int, oIdx: Int, correct: Int) -> Color {
        guard quizSubmitted else {
            return selectedAnswers[qIdx] == oIdx ? SpiralColors.accent.opacity(0.15) : SpiralColors.surface
        }
        if oIdx == correct { return SpiralColors.good.opacity(0.15) }
        if selectedAnswers[qIdx] == oIdx { return SpiralColors.poor.opacity(0.15) }
        return SpiralColors.surface
    }
}
