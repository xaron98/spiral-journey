import Foundation
import SwiftUI
import SpiralKit

#if canImport(FoundationModels)
import FoundationModels

/// On-device AI service using Apple Foundation Models (iOS 26+).
/// Provides sleep insight interpretation and dream analysis.
@Observable
@MainActor
final class OnDeviceAIService {

    var isAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    var isProcessing = false

    // MARK: - Sleep Insight Interpretation

    /// Generate a natural language summary of the user's sleep data.
    @available(iOS 26, *)
    func interpretSleepInsights(
        poisson: PoissonFragmentationResult?,
        hawkes: HawkesAnalysisResult?,
        healthMarkers: HealthMarkers,
        consistency: SpiralConsistencyScore?,
        locale: String = "es"
    ) async -> String? {
        guard isAvailable else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        let isSpanish = locale.hasPrefix("es")

        var dataContext = isSpanish ? "Datos de análisis de sueño:\n" : "Sleep analysis data:\n"

        // Poisson
        if let p = poisson {
            dataContext += "- Baseline awakening rate: \(String(format: "%.1f", p.baselineRate)) per night\n"
            dataContext += "- Awakenings follow Poisson: \(p.followsPoisson ? "yes (random)" : "no (patterned)")\n"
            dataContext += "- Anomalous nights: \(p.anomalousNights.count)\n"
        }

        // Hawkes
        if let h = hawkes {
            for impact in h.eventImpacts where impact.significantEffect {
                let direction = impact.excitationStrength > 0 ? "increases" : "decreases"
                dataContext += "- \(impact.eventType): \(direction) awakenings by \(Int(abs(impact.excitationStrength) * 100))% with ~\(Int(impact.delayHours))h delay\n"
            }
        }

        // Health markers
        dataContext += "- Circadian coherence: \(String(format: "%.0f%%", healthMarkers.circadianCoherence * 100))\n"
        dataContext += "- Fragmentation: \(String(format: "%.0f%%", healthMarkers.fragmentationScore * 100))\n"
        dataContext += "- Drift: \(String(format: "%.1f", healthMarkers.driftSeverity)) min/day\n"

        // Consistency
        if let c = consistency {
            dataContext += "- Consistency score: \(c.score)/100\n"
        }

        let instructions = isSpanish
            ? """
              Eres un intérprete de salud del sueño. Responde SIEMPRE en español.
              Dados datos numéricos de análisis de sueño, escribe un resumen breve,
              cálido y personalizado (3-4 frases máximo).
              Céntrate en lo que los datos SIGNIFICAN para el usuario, no en los números.
              Usa lenguaje sencillo. NO uses jerga médica. NO des consejos médicos.
              NO menciones Poisson, Hawkes, chi-cuadrado ni nombres de algoritmos.
              Solo explica lo que sus patrones de sueño muestran en lenguaje cotidiano.
              """
            : """
              You are a sleep health interpreter. Respond ALWAYS in English.
              Given numerical sleep analysis data, write a brief, warm, personalized
              summary (3-4 sentences max).
              Focus on what the data MEANS for the user, not the numbers themselves.
              Use simple language. DO NOT use medical jargon. DO NOT give medical advice.
              DO NOT mention Poisson, Hawkes, chi-squared, or any algorithm names.
              Just explain what their sleep patterns show in everyday language.
              """

        do {
            let session = LanguageModelSession {
                instructions
            }
            let response = try await session.respond(to: dataContext)
            return response.content
        } catch {
            return nil
        }
    }

    // MARK: - Dream Interpretation

    /// Interpret a dream and optionally find patterns with previous dreams.
    @available(iOS 26, *)
    func interpretDream(
        dreamText: String,
        sleepPhases: String,
        previousDreams: [String] = [],
        locale: String = "es"
    ) async -> String? {
        guard isAvailable, !dreamText.isEmpty else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        let isSpanish = locale.hasPrefix("es")

        var prompt = isSpanish
            ? "Sueño de anoche: \"\(dreamText)\"\nContexto de sueño: \(sleepPhases)\n"
            : "Dream from last night: \"\(dreamText)\"\nSleep context: \(sleepPhases)\n"

        if !previousDreams.isEmpty {
            prompt += isSpanish ? "\nSueños anteriores para comparar patrones:\n" : "\nPrevious dreams for pattern comparison:\n"
            for (i, dream) in previousDreams.prefix(5).enumerated() {
                prompt += "- \(isSpanish ? "Sueño" : "Dream") \(i + 1): \"\(dream)\"\n"
            }
        }

        let instructions = isSpanish
            ? """
              Eres un compañero de diario de sueños. Responde SIEMPRE en español.
              Dado un sueño y su contexto, proporciona:
              1. Una interpretación breve y reflexiva (2-3 frases) — qué temas o emociones destacan
              2. Si hay sueños anteriores, menciona temas recurrentes o patrones (1-2 frases)

              Sé exploratorio y curioso, nunca definitivo. Los sueños son personales.
              NO des diagnósticos psicológicos. NO afirmes precisión científica.
              Esto es solo para autorreflexión.
              """
            : """
              You are a dream journal companion. Respond ALWAYS in English.
              Given a dream description and sleep context, provide:
              1. A brief, thoughtful interpretation (2-3 sentences) — what themes or emotions stand out
              2. If previous dreams are provided, note any recurring themes or patterns (1-2 sentences)

              Keep it exploratory and curious, never definitive. Dreams are personal.
              DO NOT provide psychological diagnosis. DO NOT claim scientific accuracy.
              This is for self-reflection only.
              """

        do {
            let session = LanguageModelSession {
                instructions
            }
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return nil
        }
    }
}

#else

/// Fallback for platforms without Foundation Models.
@Observable
@MainActor
final class OnDeviceAIService {
    var isAvailable: Bool { false }
    var isProcessing = false
}

#endif
