import Foundation

/// Picks the best available ``CoachLLMProvider`` for the current device.
///
/// On iOS 26+ with Apple Intelligence hardware (A17 Pro / M-series), returns
/// ``FoundationModelsProvider`` for instant, download-free inference.
/// Otherwise falls back to ``PhiLLMProvider`` (Phi-3.5 Mini via GGUF).
@MainActor
struct CoachProviderFactory {

    static func makeProvider(llmService: LLMService) -> any CoachLLMProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            let fm = FoundationModelsProvider()
            if fm.isAvailable { return fm }
        }
        #endif
        return PhiLLMProvider(llmService: llmService)
    }
}
