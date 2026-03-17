import Foundation
import SpiralKit
import LLM

// MARK: - Prompt Capability

/// Determines the prompt tier based on the backing LLM provider.
enum PromptCapability {
    /// Phi-3.5 — compact prompt, no extra prediction data.
    case compact
    /// Foundation Models — richer prompt with prediction data and model accuracy.
    case rich
}

// MARK: - LLM Context Builder

/// Builds the system prompt for the on-device LLM coach chat.
///
/// Injects the user's sleep profile (~800 tokens) so the model has personal context.
/// Keeps the prompt compact to fit within the 2048-token context window.
enum LLMContextBuilder {

    /// Maximum number of history messages to keep for the given capability tier.
    static func maxHistoryMessages(for capability: PromptCapability) -> Int {
        switch capability {
        case .compact: return 10   // Phi library truncates internally to 4
        case .rich:    return 10
        }
    }

    /// Build the system prompt from the current analysis state.
    static func buildSystemPrompt(
        analysis: AnalysisResult,
        goal: SleepGoal,
        records: [SleepRecord],
        locale: Locale = .current
    ) -> String {
        buildSystemPrompt(
            analysis: analysis,
            goal: goal,
            records: records,
            locale: locale,
            capability: .compact,
            prediction: nil,
            modelAccuracy: nil
        )
    }

    /// Enhanced system prompt that optionally includes prediction data and SleepDNA insights.
    ///
    /// When `capability` is `.rich` and a `prediction` is provided, the prompt
    /// appends tonight's predicted bedtime and (optionally) the model accuracy.
    /// When a `dnaProfile` is provided, key SleepDNA insights are injected.
    static func buildSystemPrompt(
        analysis: AnalysisResult,
        goal: SleepGoal,
        records: [SleepRecord],
        locale: Locale = .current,
        capability: PromptCapability,
        prediction: PredictionOutput?,
        modelAccuracy: Double?,
        dnaProfile: SleepDNAProfile? = nil
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

        // 8. Prediction data (rich tier only)
        if capability == .rich, let prediction = prediction {
            let bedtimeStr = SleepStatistics.formatHour(prediction.predictedBedtimeHour)
            let predHeader = isSpanish ? "PREDICCIÓN PARA ESTA NOCHE:" : "TONIGHT'S PREDICTION:"
            parts.append(predHeader)
            if isSpanish {
                parts.append("- Hora estimada de dormir: \(bedtimeStr)")
            } else {
                parts.append("- Predicted bedtime: \(bedtimeStr)")
            }
            if let accuracy = modelAccuracy {
                let pct = String(format: "%.0f%%", accuracy * 100)
                if isSpanish {
                    parts.append("- Precisión del modelo: \(pct)")
                } else {
                    parts.append("- Model accuracy: \(pct)")
                }
            }
        }

        // 9. SleepDNA insights — structured compact summary (rich tier only)
        if capability == .rich, let dna = dnaProfile {
            parts.append("SLEEP DNA ANALYSIS:")
            parts.append("Tier: \(dna.tier.rawValue) (\(dna.dataWeeks) weeks)")

            // HAS — habit stability
            if let has = dna.hasScore {
                parts.append("HAS: \(String(format: "%.2f", has)) (habit stability)")
            }
            // Baseline HAS — vs 4-week average
            if let baseline = dna.baselineHAS {
                parts.append("Baseline: \(String(format: "%.2f", baseline)) (vs 4-week average)")
            }

            // Health markers (compact key-value lines)
            let hm = dna.healthMarkers
            parts.append("HB: \(String(format: "%.2f", hm.homeostasisBalance)) (circadian-homeostatic balance)")
            parts.append("HCI: \(String(format: "%.2f", hm.helicalContinuity)) (sleep continuity)")
            if let rds = hm.remDriftSlope {
                let sign = rds >= 0 ? "+" : ""
                parts.append("RDS: \(sign)\(String(format: "%.0f", rds * 60)) min/day (REM drift)")
            }
            if let rce = hm.remClusterEntropy {
                parts.append("RCE: \(String(format: "%.2f", rce)) (REM coherence)")
            }
            parts.append("Drift: \(String(format: "%.0f", hm.driftSeverity)) min/day")
            parts.append("Coherence: \(String(format: "%.2f", hm.circadianCoherence))")

            // Active pattern — most frequent motif
            if let topMotif = dna.motifs.first {
                let weekCount = topMotif.instanceCount
                parts.append("Active pattern: \"\(topMotif.name)\" (\(weekCount) instances)")
            }

            // Recent mutation — last non-silent mutation
            if let recentMutation = dna.mutations.last(where: { $0.classification != .silent }) {
                let sign = recentMutation.qualityDelta >= 0 ? "+" : ""
                let pct = String(format: "%.0f", recentMutation.qualityDelta * 100)
                parts.append("Recent mutation: \(recentMutation.classification.rawValue) (\(sign)\(pct)% quality)")
            }

            // Similar week — best historical alignment
            if let bestAlignment = dna.alignments.first {
                let simPct = String(format: "%.0f", bestAlignment.similarity * 100)
                parts.append("Similar week: day \(bestAlignment.startDay) (\(simPct)%)")
            }

            // Top influences — up to 2 strongest synchrony pairs
            let topPairs = dna.basePairs.prefix(2)
            if !topPairs.isEmpty {
                let pairStrs = topPairs.map { pair -> String in
                    let sleepLabel = Self.featureLabel(pair.sleepFeatureIndex)
                    let ctxLabel = Self.featureLabel(pair.contextFeatureIndex)
                    return "\(ctxLabel)\u{2192}\(sleepLabel) (PLV \(String(format: "%.2f", pair.plv)))"
                }
                parts.append("Top influences: \(pairStrs.joined(separator: ", "))")
            }

            // Alerts
            if dna.healthMarkers.alerts.isEmpty {
                parts.append("Alerts: none")
            } else {
                for alert in dna.healthMarkers.alerts.prefix(3) {
                    parts.append("Alert [\(alert.severity.rawValue)]: \(alert.message)")
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Feature Labels

    /// Compact human-readable label for a DayNucleotide feature index.
    private static func featureLabel(_ index: Int) -> String {
        switch DayNucleotide.Feature(rawValue: index) {
        case .bedtimeSin, .bedtimeCos: return "bedtime"
        case .wakeupSin, .wakeupCos:   return "wakeup"
        case .sleepDuration:           return "duration"
        case .processS:                return "sleep-pressure"
        case .cosinorAcrophase:        return "acrophase"
        case .cosinorR2:               return "rhythm"
        case .caffeine:                return "caffeine"
        case .exercise:                return "exercise"
        case .alcohol:                 return "alcohol"
        case .melatonin:               return "melatonin"
        case .stress:                  return "stress"
        case .isWeekend:               return "weekend"
        case .driftMinutes:            return "drift"
        case .sleepQuality:            return "quality"
        case .none:                    return "f\(index)"
        }
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
