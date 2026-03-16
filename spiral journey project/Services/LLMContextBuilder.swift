import Foundation
import SpiralKit
import LLM

// MARK: - LLM Context Builder

/// Builds the system prompt for the on-device LLM coach chat.
///
/// Injects the user's sleep profile (~800 tokens) so the model has personal context.
/// Keeps the prompt compact to fit within the 2048-token context window.
enum LLMContextBuilder {

    /// Build the system prompt from the current analysis state.
    static func buildSystemPrompt(
        analysis: AnalysisResult,
        goal: SleepGoal,
        records: [SleepRecord],
        locale: Locale = .current
    ) -> String {
        let isSpanish = locale.language.languageCode?.identifier == "es"

        var parts: [String] = []

        // 1. Role definition
        if isSpanish {
            parts.append("""
            Eres un coach de sueño experto integrado en la app Spiral Journey. \
            Responde siempre en español. Sé breve, empático y basado en evidencia. \
            No des diagnósticos médicos. Usa los datos del usuario para personalizar tus respuestas.
            """)
        } else {
            parts.append("""
            You are an expert sleep coach integrated into the Spiral Journey app. \
            Be concise, empathetic, and evidence-based. \
            Never give medical diagnoses. Use the user's data to personalize your responses.
            """)
        }

        // 2. Sleep profile summary
        let stats = analysis.stats
        let composite = analysis.composite
        let label = analysis.label

        let profileHeader = isSpanish ? "PERFIL DE SUEÑO DEL USUARIO:" : "USER SLEEP PROFILE:"
        parts.append(profileHeader)

        let bedtimeStr = SleepStatistics.formatHour(stats.meanAcrophase > 0 ? stats.meanAcrophase - stats.meanAmplitude : goal.targetBedHour)
        let durationStr = String(format: "%.1f", stats.meanSleepDuration)
        let sriStr = String(format: "%.0f", stats.sri)

        if isSpanish {
            parts.append("""
            - Puntuación compuesta: \(composite)/100 (\(label))
            - Duración media del sueño: \(durationStr)h (objetivo: \(String(format: "%.1f", goal.targetDuration))h)
            - Regularidad (SRI): \(sriStr)/100
            - Jet lag social: \(String(format: "%.0f", stats.socialJetlag)) min
            - Estabilidad del ritmo: \(String(format: "%.0f%%", stats.rhythmStability * 100))
            """)
        } else {
            parts.append("""
            - Composite score: \(composite)/100 (\(label))
            - Mean sleep duration: \(durationStr)h (goal: \(String(format: "%.1f", goal.targetDuration))h)
            - Regularity (SRI): \(sriStr)/100
            - Social jetlag: \(String(format: "%.0f", stats.socialJetlag)) min
            - Rhythm stability: \(String(format: "%.0f%%", stats.rhythmStability * 100))
            """)
        }

        // 3. Current issue
        if let insight = analysis.coachInsight {
            let issueHeader = isSpanish ? "PROBLEMA ACTUAL:" : "CURRENT ISSUE:"
            parts.append(issueHeader)
            parts.append("- \(insight.issueKey.rawValue): \(insight.title)")
            parts.append("- \(insight.reason)")
        }

        // 4. Trends
        let trends = analysis.trends
        if !trends.improving.isEmpty {
            let label = isSpanish ? "MEJORANDO:" : "IMPROVING:"
            parts.append(label)
            for t in trends.improving.prefix(2) {
                parts.append("- \(t.label): \(t.detail)")
            }
        }
        if !trends.deteriorating.isEmpty {
            let label = isSpanish ? "EMPEORANDO:" : "DETERIORATING:"
            parts.append(label)
            for t in trends.deteriorating.prefix(2) {
                parts.append("- \(t.label): \(t.detail)")
            }
        }

        // 5. Enhanced coach data
        if let enhanced = analysis.enhancedCoach {
            if let digest = enhanced.weeklyDigest, digest.isValid {
                let label = isSpanish ? "RESUMEN SEMANAL:" : "WEEKLY SUMMARY:"
                parts.append(label)
                let durDelta = String(format: "%+.0f", digest.durationDeltaMinutes)
                let sriDelta = String(format: "%+.0f", digest.sriDelta)
                if isSpanish {
                    parts.append("- Cambio duración: \(durDelta) min, Cambio SRI: \(sriDelta)")
                } else {
                    parts.append("- Duration change: \(durDelta) min, SRI change: \(sriDelta)")
                }
            }
            if enhanced.streak.isActive {
                let label = isSpanish ? "RACHA:" : "STREAK:"
                parts.append("\(label) \(enhanced.streak.currentStreak) noches")
            }
        }

        // 6. Goal context
        let goalHeader = isSpanish ? "OBJETIVO:" : "GOAL:"
        parts.append(goalHeader)
        if isSpanish {
            parts.append("- Modo: \(goal.mode.rawValue), Dormir: \(SleepStatistics.formatHour(goal.targetBedHour))–\(SleepStatistics.formatHour(goal.targetWakeHour)), \(String(format: "%.0f", goal.targetDuration))h")
        } else {
            parts.append("- Mode: \(goal.mode.rawValue), Sleep: \(SleepStatistics.formatHour(goal.targetBedHour))–\(SleepStatistics.formatHour(goal.targetWakeHour)), \(String(format: "%.0f", goal.targetDuration))h")
        }

        // 7. Behavioral guidelines
        if isSpanish {
            parts.append("""
            REGLAS:
            - Respuestas cortas (2-4 frases). No uses listas largas.
            - Basa los consejos en los datos del usuario.
            - Si preguntan algo fuera del sueño, redirige amablemente.
            - Nunca inventes datos que no tienes.
            """)
        } else {
            parts.append("""
            RULES:
            - Keep responses short (2-4 sentences). No long lists.
            - Base advice on the user's data above.
            - If asked about non-sleep topics, gently redirect.
            - Never fabricate data you don't have.
            """)
        }

        return parts.joined(separator: "\n")
    }

    /// Build a trimmed chat history suitable for context injection.
    /// Keeps the last N messages to stay within token budget.
    static func trimHistory(_ messages: [ChatMessage], maxMessages: Int = 10) -> [(role: Role, content: String)] {
        let recent = messages.suffix(maxMessages)
        return recent.compactMap { msg in
            switch msg.role {
            case .user:      return (role: .user, content: msg.content)
            case .assistant: return (role: .bot, content: msg.content)
            case .system:    return nil
            }
        }
    }
}
