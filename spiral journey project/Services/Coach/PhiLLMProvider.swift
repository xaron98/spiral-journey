import Foundation

/// ``CoachLLMProvider`` backed by the on-device Phi-3.5 Mini model.
///
/// Thin adapter around ``LLMService`` that maps its state to the
/// protocol's ``CoachProviderState`` and wraps the non-throwing
/// `generate` call in an ``AsyncThrowingStream``.
@Observable
@MainActor
final class PhiLLMProvider: CoachLLMProvider {

    // MARK: - Dependencies

    private let llmService: LLMService

    // MARK: - Init

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    // MARK: - CoachLLMProvider

    nonisolated var displayName: String { "Phi-3.5 Mini" }

    nonisolated var requiresDownload: Bool { true }

    var isAvailable: Bool {
        llmService.state == .ready
    }

    var providerState: CoachProviderState {
        Self.mapState(llmService.state)
    }

    func generate(prompt: String, systemContext: String) async throws -> AsyncThrowingStream<String, Error> {
        guard llmService.state == .ready else {
            throw CoachLLMError.unavailable
        }

        // LLMService.generate is non-throwing and returns the full response.
        // We wrap it in an AsyncThrowingStream that yields the complete text
        // as a single chunk so the chat layer has a uniform streaming API.
        let service = llmService
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                let response = await service.generate(prompt: prompt, systemContext: systemContext)
                if response.isEmpty {
                    continuation.finish(throwing: CoachLLMError.generationFailed("Model returned an empty response"))
                } else {
                    continuation.yield(response)
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Model Lifecycle

    /// Download the model weights (delegates to ``LLMService``).
    func downloadModel() async {
        await llmService.downloadModel()
    }

    /// Load the model into memory (delegates to ``LLMService``).
    func loadModel() async {
        await llmService.loadModel()
    }

    /// Unload the model from memory (delegates to ``LLMService``).
    func unloadModel() {
        llmService.unloadModel()
    }

    // MARK: - Helpers

    /// Map ``LLMState`` → ``CoachProviderState``.
    private static func mapState(_ state: LLMState) -> CoachProviderState {
        switch state {
        case .notDownloaded:            return .notDownloaded
        case .downloading(let p):       return .downloading(progress: p)
        case .downloaded:               return .notDownloaded   // downloaded but not loaded → not ready
        case .loading:                  return .loading
        case .ready:                    return .ready
        case .error(let msg):           return .error(msg)
        }
    }
}
