import Foundation
import os
import SwiftUI
import SpiralKit
import LLM

// MARK: - LLM State

/// Lifecycle states for the on-device language model.
enum LLMState: Equatable {
    case notDownloaded          // Model file not present
    case downloading(Double)    // Downloading from HuggingFace (0…1 progress)
    case downloaded             // File on disk but model not loaded in memory
    case loading                // Loading into RAM / Metal
    case ready                  // Model loaded and ready to chat
    case error(String)          // Something went wrong

    var isUsable: Bool { self == .ready }
    var isError: Bool { if case .error = self { return true } else { return false } }

    var statusText: String {
        switch self {
        case .notDownloaded:      return "Not downloaded"
        case .downloading(let p): return "Downloading… \(Int(p * 100))%"
        case .downloaded:         return "Ready to load"
        case .loading:            return "Loading model…"
        case .ready:              return "Ready"
        case .error(let msg):     return "Error: \(msg)"
        }
    }
}

// MARK: - LLM Service

/// Manages an on-device LLM for the coach chat.
///
/// - Downloads a GGUF model from HuggingFace on first use.
/// - Loads / unloads the model on demand.
/// - Streams tokens for the chat UI.
///
/// Only used on the iOS target — never imported by watchOS or SpiralKit.

/// Targeted Sendable escape hatch for the LLM library type which
/// doesn't conform to Sendable. Safe because the value is created
/// on MainActor, sent to a detached task for inference, and never
/// accessed concurrently — ownership transfers linearly.
private struct SendableBox<T>: @unchecked Sendable { let value: T }

@Observable
@MainActor
final class LLMService {

    // MARK: - Configuration

    /// Direct download URL for the GGUF model (~2.4 GB).
    /// Using a direct resolve URL instead of HuggingFaceModel.download()
    /// because the library scrapes HTML which is fragile with HuggingFace's JS rendering.
    private static let modelDownloadURL = URL(
        string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"
    )!

    /// Local filename for the downloaded GGUF.
    private static let modelFilename = "Phi-3.5-mini-instruct-Q4_K_M.gguf"

    /// Directory where the model file is stored.
    private static var modelsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("models")
    }

    /// Full path to the model file.
    private static var modelPath: URL {
        modelsDir.appendingPathComponent(modelFilename)
    }

    // MARK: - Published State

    private(set) var state: LLMState = .notDownloaded
    private(set) var streamingText: String = ""
    private(set) var isGenerating: Bool = false

    // MARK: - Private

    private var llm: LLM?
    private nonisolated(unsafe) var memoryWarningObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        // Check if model file exists on disk
        if FileManager.default.fileExists(atPath: Self.modelPath.path) {
            state = .downloaded
        }
        // Observe memory warnings to auto-unload
        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.unloadModel()
            }
        }
        #endif
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Model Size

    /// Size of the downloaded model file in bytes, or nil if not downloaded.
    var modelFileSize: Int64? {
        guard FileManager.default.fileExists(atPath: Self.modelPath.path) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.modelPath.path)
        return attrs?[.size] as? Int64
    }

    /// Human-readable model size string.
    var modelFileSizeString: String {
        guard let size = modelFileSize else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Download

    /// Download the model from HuggingFace using a direct URL.
    func downloadModel() async {
        guard state == .notDownloaded || state.isError else { return }

        // Ensure models directory exists
        try? FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        let destination = Self.modelPath
        // Skip if file already exists
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            state = .downloaded
            return
        }

        state = .downloading(0)

        do {
            // Use URLSession downloadTask with progress observation
            let (tempURL, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                let task = URLSession.shared.downloadTask(with: Self.modelDownloadURL) { url, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url, let response {
                        continuation.resume(returning: (url, response))
                    } else {
                        continuation.resume(throwing: URLError(.unknown))
                    }
                }

                // Observe download progress
                let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.state = .downloading(progress.fractionCompleted)
                    }
                }
                // Keep observation alive until task completes
                objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

                task.resume()
            }

            // Verify HTTP status
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode / 100 != 2 {
                state = .error("Download failed: HTTP \(httpResponse.statusCode)")
                return
            }

            // Move downloaded file to final destination
            try FileManager.default.moveItem(at: tempURL, to: destination)
            state = .downloaded
        } catch {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load / Unload

    /// Load the model into memory. Call this before chatting.
    func loadModel() async {
        guard case .downloaded = state else { return }
        state = .loading

        // Load on a background thread to keep UI responsive.
        // Start with 1024 context; if that fails (OOM), retry with 512.
        let path = Self.modelPath
        let loaded: LLM? = await Task.detached(priority: .userInitiated) {
            // Try 1024-token context first (moderate KV cache ~384 MB)
            if let model = LLM(from: path, template: .chatML(), maxTokenCount: 1024) {
                return model
            }
            // Fallback to 512-token context (~192 MB KV cache)
            return LLM(from: path, template: .chatML(), maxTokenCount: 512)
        }.value

        if let loaded {
            llm = loaded
            llm?.temp = 0.7
            llm?.topP = 0.9
            llm?.topK = 40
            llm?.historyLimit = 4   // Keep last 2 exchanges to fit in small context
            state = .ready
        } else {
            state = .error("Failed to load model")
        }
    }

    /// Unload the model from memory.
    func unloadModel() {
        llm = nil
        if FileManager.default.fileExists(atPath: Self.modelPath.path) {
            state = .downloaded
        } else {
            state = .notDownloaded
        }
        isGenerating = false
        streamingText = ""
    }

    // MARK: - Delete

    /// Delete the downloaded model file and unload from memory.
    func deleteModel() {
        unloadModel()
        try? FileManager.default.removeItem(at: Self.modelPath)
        try? FileManager.default.removeItem(at: Self.modelsDir)
        state = .notDownloaded
    }

    // MARK: - Generate

    /// ChatML special tokens that must never appear in user-visible output.
    /// The library's stop-sequence is set async via `template.didSet`, which can
    /// race with `respond(to:)`. We catch them here as a safety net.
    private static let chatMLStopTokens = ["<|im_end|>", "<|im_start|>"]

    /// Generate a response by streaming tokens.
    /// Returns the full response text when complete.
    ///
    /// Uses a thread-safe buffer to batch token updates (~80 ms) so the main
    /// thread isn't flooded with one dispatch per token.
    @discardableResult
    func generate(prompt: String, systemContext: String) async -> String {
        guard !isGenerating else { return "" }
        guard let llm, state == .ready else { return "" }

        isGenerating = true
        streamingText = ""

        // Set system prompt via template
        llm.template = .chatML(systemContext)

        // Thread-safe token buffer — accumulates tokens from the inference
        // thread and is drained to the UI every ~80 ms.
        let buffer = OSAllocatedUnfairLock(initialState: "")

        // Streaming callback — runs on the inference thread, never touches UI directly.
        llm.update = { [weak self] delta in
            guard self != nil else { return }
            if let delta {
                // Stop immediately if a ChatML control token leaks through
                if Self.chatMLStopTokens.contains(where: { delta.contains($0) }) {
                    Task { @MainActor in
                        self?.llm?.stop()
                        self?.isGenerating = false
                    }
                    return
                }
                // Accumulate in buffer — no per-token main-actor dispatch
                buffer.withLock { $0 += delta }
            } else {
                // nil → generation complete; flush remaining buffer
                let remaining = buffer.withLock { b in let r = b; b = ""; return r }
                Task { @MainActor in
                    if !remaining.isEmpty { self?.streamingText += remaining }
                    self?.isGenerating = false
                }
            }
        }

        // Periodic UI flush — drains buffer onto streamingText every ~80 ms
        // instead of once per token, keeping the main thread responsive.
        let flushTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, self.isGenerating else { break }
                let batch = buffer.withLock { b in let r = b; b = ""; return r }
                if !batch.isEmpty {
                    self.streamingText += batch
                }
            }
        }

        // Run inference OFF the main actor so UI stays fully responsive.
        // SendableBox is safe: only one generation runs at a time.
        let model = SendableBox(value: llm)
        let userPrompt = prompt
        await Task.detached(priority: .userInitiated) {
            await model.value.respond(to: userPrompt)
        }.value

        // Tear down: cancel flush timer and drain any remaining tokens
        flushTask.cancel()
        let remaining = buffer.withLock { b in let r = b; b = ""; return r }
        if !remaining.isEmpty { streamingText += remaining }
        isGenerating = false

        // Strip any residual control tokens
        var result = streamingText
        for token in Self.chatMLStopTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stop the current generation.
    func stopGeneration() {
        llm?.stop()
        isGenerating = false
    }
}
