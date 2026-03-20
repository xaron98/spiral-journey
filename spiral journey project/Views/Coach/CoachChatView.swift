import SwiftUI
import SwiftData
import SpiralKit

/// Full-screen chat sheet for the AI coach.
///
/// Presented as a sheet from CoachTab when the user taps the chat button.
/// Shows download prompt when model is not available, streaming chat when ready.
///
/// Uses ``CoachProviderFactory`` to pick the best backend:
/// - Apple Intelligence (Foundation Models) on iOS 26+ with capable hardware — instant, no download.
/// - Phi-3.5 Mini (GGUF) everywhere else — requires download + load.
struct CoachChatView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(LLMService.self) private var llm
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var streamingText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    /// Maximum messages to keep in the conversation.
    private let maxMessages = 50

    /// The provider is resolved once via the factory and kept for the view's lifetime.
    /// Passed in from the app entry point through the environment or created here.
    @State private var provider: (any CoachLLMProvider)?

    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                if let provider, !provider.requiresDownload {
                    // Foundation Models path — no download/load needed
                    chatView
                } else {
                    // Phi path — show download/load flow based on LLMService state
                    switch llm.state {
                    case .notDownloaded, .error:
                        downloadPrompt
                    case .downloading(let progress):
                        downloadingView(progress)
                    case .downloaded:
                        loadingPrompt
                    case .loading:
                        loadingView
                    case .ready:
                        chatView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.footnote)
                                .foregroundStyle(SpiralColors.accent)
                            Text(loc("coach.chat.title"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SpiralColors.text)
                        }
                        if let provider {
                            Text(provider.displayName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(SpiralColors.faint)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
        .onAppear {
            // Resolve provider on first appear
            if provider == nil {
                provider = CoachProviderFactory.makeProvider(llmService: llm)
            }
            messages = store.chatHistory
            // Auto-load Phi if already downloaded
            if provider?.requiresDownload == true, llm.state == .downloaded {
                Task { await llm.loadModel() }
            }
        }
        .onDisappear {
            // Cancel any in-flight generation
            generationTask?.cancel()
            generationTask = nil
            isGenerating = false
            streamingText = ""
            // Auto-unload Phi when leaving chat to free memory
            if provider?.requiresDownload == true {
                llm.unloadModel()
            }
        }
    }

    // MARK: - Download Prompt

    private var downloadPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(SpiralColors.accent)

            Text(loc("coach.chat.download.title"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(SpiralColors.text)

            Text(loc("coach.chat.download.subtitle"))
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Size info
            Text(loc("coach.chat.download.size"))
                .font(.caption.monospaced())
                .foregroundStyle(SpiralColors.subtle)

            Button {
                Task { await llm.downloadModel() }
            } label: {
                Label(loc("coach.chat.download.button"), systemImage: "arrow.down.to.line")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(SpiralColors.accent.opacity(0.9), in: Capsule())
            }

            // Privacy note
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text(loc("coach.chat.privacy"))
                    .font(.caption)
            }
            .foregroundStyle(SpiralColors.subtle)

            if case .error(let msg) = llm.state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.poor)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Downloading

    private func downloadingView(_ progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .tint(SpiralColors.accent)
                .frame(width: 200)

            Text(loc("coach.chat.downloading"))
                .font(.body)
                .foregroundStyle(SpiralColors.muted)

            Text("\(Int(progress * 100))%")
                .font(.title2.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.text)
        }
    }

    // MARK: - Loading Prompt

    private var loadingPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(SpiralColors.accent)

            Text(loc("coach.chat.load.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpiralColors.text)

            Button {
                Task { await llm.loadModel() }
            } label: {
                Label(loc("coach.chat.load.button"), systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(SpiralColors.accent.opacity(0.9), in: Capsule())
            }
        }
    }

    // MARK: - Loading Spinner

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SpiralColors.accent)

            Text(loc("coach.chat.loading"))
                .font(.body)
                .foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }

                        // Streaming indicator
                        if isGenerating {
                            streamingBubble
                                .id("streaming")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: streamingText) {
                    if isGenerating {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onTapGesture {
                    isInputFocused = false
                }
            }

            Divider()
                .overlay(SpiralColors.border)

            // Input bar
            inputBar
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : SpiralColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(SpiralColors.accent.opacity(0.85))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.faint)
            }

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if streamingText.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(SpiralColors.muted)
                                .frame(width: 6, height: 6)
                                .opacity(0.6)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    Text(streamingText)
                        .font(.body)
                        .foregroundStyle(SpiralColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 48)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(loc("coach.chat.placeholder"), text: $inputText, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isGenerating
                            ? SpiralColors.muted
                            : SpiralColors.accent
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isGenerating)
            .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SpiralColors.bg)
    }

    // MARK: - Actions

    private func sendMessage() {
        if isGenerating {
            generationTask?.cancel()
            generationTask = nil
            isGenerating = false
            // Commit whatever we've streamed so far
            finalizeStreamingResponse()
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        let userMsg = ChatMessage.user(text)
        messages.append(userMsg)
        inputText = ""

        // Trim if over limit
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }

        // Save to store
        store.chatHistory = messages

        // Generate response via provider
        generationTask = Task {
            guard let provider else { return }

            // Fetch latest questionnaire from SwiftData
            let latestQuestionnaire = Self.fetchLatestQuestionnaire(context: modelContext)

            let systemPrompt = LLMContextBuilder.buildSystemPrompt(
                analysis: store.analysis,
                goal: store.sleepGoal,
                records: store.records,
                capability: .compact,
                prediction: nil,
                modelAccuracy: nil,
                dnaProfile: dnaService.latestProfile,
                questionnaire: latestQuestionnaire
            )

            isGenerating = true
            streamingText = ""

            do {
                let stream = try await provider.generate(prompt: text, systemContext: systemPrompt)
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    streamingText += chunk
                }
            } catch is CancellationError {
                // User cancelled — keep whatever was streamed
            } catch {
                if streamingText.isEmpty {
                    streamingText = loc("coach.chat.error")
                }
            }

            isGenerating = false
            finalizeStreamingResponse()
        }
    }

    /// Commit the accumulated streaming text as an assistant message.
    private func finalizeStreamingResponse() {
        let response = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        streamingText = ""
        guard !response.isEmpty else { return }
        let assistantMsg = ChatMessage(role: .assistant, content: response)
        messages.append(assistantMsg)
        store.chatHistory = messages
    }

    // MARK: - Questionnaire Fetch

    /// Fetch the most recent weekly questionnaire response from SwiftData.
    private static func fetchLatestQuestionnaire(context: ModelContext) -> SDQuestionnaireResponse? {
        var descriptor = FetchDescriptor<SDQuestionnaireResponse>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
