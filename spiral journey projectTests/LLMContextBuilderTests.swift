import Testing
import Foundation
@testable import SpiralKit
@testable import spiral_journey_project

@Suite("LLMContextBuilder")
struct LLMContextBuilderTests {

    // MARK: - System Prompt

    @Test("System prompt contains sleep profile data")
    func testSystemPromptContainsProfile() {
        let stats = SleepStats(
            meanAcrophase: 15.0,
            stdAcrophase: 0.5,
            meanAmplitude: 4.0,
            rhythmStability: 0.75,
            socialJetlag: 45.0,
            meanSleepDuration: 7.2,
            sri: 72
        )
        let analysis = AnalysisResult(
            composite: 68,
            label: "Good",
            stats: stats,
            coachInsight: CoachInsight(
                issueKey: .delayedPhase,
                title: "Delayed sleep phase",
                reason: "You sleep later than ideal",
                action: "Get morning light",
                expectedOutcome: "Shift bedtime earlier",
                severity: .moderate
            )
        )
        let goal = SleepGoal.generalHealthDefault

        let prompt = LLMContextBuilder.buildSystemPrompt(
            analysis: analysis,
            goal: goal,
            records: [],
            locale: Locale(identifier: "en")
        )

        #expect(prompt.contains("68/100"))
        #expect(prompt.contains("7.2h"))
        #expect(prompt.contains("delayedPhase"))
        #expect(prompt.contains("CURRENT ISSUE") || prompt.contains("PROBLEMA ACTUAL"))
    }

    @Test("System prompt in Spanish uses Spanish labels")
    func testSystemPromptSpanish() {
        let analysis = AnalysisResult(composite: 50, label: "Moderate", stats: SleepStats(sri: 55))
        let goal = SleepGoal.generalHealthDefault

        let prompt = LLMContextBuilder.buildSystemPrompt(
            analysis: analysis,
            goal: goal,
            records: [],
            locale: Locale(identifier: "es")
        )

        #expect(prompt.contains("Eres un coach de sueño"))
        #expect(prompt.contains("PERFIL DE SUEÑO"))
        #expect(prompt.contains("OBJETIVO"))
    }

    @Test("System prompt contains goal info")
    func testSystemPromptGoal() {
        let analysis = AnalysisResult()
        let goal = SleepGoal(
            mode: .shiftWork,
            targetBedHour: 22.0,
            targetWakeHour: 6.0,
            targetDuration: 8.0,
            toleranceMinutes: 60
        )

        let prompt = LLMContextBuilder.buildSystemPrompt(
            analysis: analysis,
            goal: goal,
            records: [],
            locale: Locale(identifier: "en")
        )

        #expect(prompt.contains("shiftWork"))
        #expect(prompt.contains("GOAL") || prompt.contains("OBJETIVO"))
    }

    // MARK: - Chat History Trimming

    @Test("trimHistory limits to maxMessages")
    func testTrimHistoryLimit() {
        var messages: [ChatMessage] = []
        for i in 0..<20 {
            messages.append(ChatMessage.user("msg \(i)"))
        }

        let trimmed = LLMContextBuilder.trimHistory(messages, maxMessages: 5)
        #expect(trimmed.count == 5)
    }

    @Test("trimHistory filters system messages")
    func testTrimHistoryFiltersSystem() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "system"),
            ChatMessage.user("hello"),
            ChatMessage(role: .assistant, content: "hi"),
        ]

        let trimmed = LLMContextBuilder.trimHistory(messages)
        #expect(trimmed.count == 2) // system filtered out
    }
}
