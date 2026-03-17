import Foundation

// MARK: - Provider Protocol

/// Abstraction over on-device language models used by the AI Coach.
///
/// Concrete implementations (e.g. ``PhiLLMProvider``, ``FoundationModelsProvider``)
/// wrap a specific runtime and expose a uniform streaming interface so the chat
/// layer never depends on a particular model backend.
protocol CoachLLMProvider: Sendable {
    /// Whether the provider is ready to generate text right now.
    var isAvailable: Bool { get }

    /// Human-readable name shown in settings / UI (e.g. "Phi-3.5 Mini").
    var displayName: String { get }

    /// `true` when the model weights must be downloaded before first use.
    var requiresDownload: Bool { get }

    /// Current lifecycle state of the provider.
    var providerState: CoachProviderState { get }

    /// Stream a response for the given prompt.
    ///
    /// The stream may yield one or many chunks depending on the backend.
    /// Callers should concatenate chunks to build the full reply.
    func generate(prompt: String, systemContext: String) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Provider State

/// Lifecycle states shared across all ``CoachLLMProvider`` implementations.
enum CoachProviderState: Sendable {
    case ready
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case error(String)
}

// MARK: - Errors

/// Errors surfaced by ``CoachLLMProvider`` implementations.
enum CoachLLMError: Error, LocalizedError {
    /// The model is not available (not downloaded, not loaded, unsupported device, etc.).
    case unavailable
    /// Generation started but produced no usable output.
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Language model not available on this device"
        case .generationFailed(let msg):
            "Generation failed: \(msg)"
        }
    }
}
