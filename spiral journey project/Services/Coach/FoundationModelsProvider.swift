import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// ``CoachLLMProvider`` backed by Apple's Foundation Models framework (iOS 26+).
///
/// Uses the on-device system language model (Apple Intelligence) for zero-download,
/// zero-cost inference. Falls back gracefully when the hardware or OS doesn't support it.
@available(iOS 26, *)
@Observable
@MainActor
final class FoundationModelsProvider: CoachLLMProvider {

    // MARK: - State

    private var session: LanguageModelSession?

    // MARK: - CoachLLMProvider

    nonisolated var displayName: String { "Apple Intelligence" }

    nonisolated var requiresDownload: Bool { false }

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    var providerState: CoachProviderState {
        if isAvailable { return .ready }
        return .notDownloaded   // device not eligible or AI not enabled
    }

    func generate(prompt: String, systemContext: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else {
            throw CoachLLMError.unavailable
        }

        // Create a fresh session with the system prompt each time so the
        // context stays small (the on-device model has a limited token window).
        let currentSession = LanguageModelSession {
            systemContext
        }
        self.session = currentSession

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = currentSession.streamResponse(to: prompt)
                    var previousLength = 0
                    for try await snapshot in stream {
                        let content = snapshot.content
                        if content.count > previousLength {
                            let delta = String(content.dropFirst(previousLength))
                            continuation.yield(delta)
                            previousLength = content.count
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
#endif
