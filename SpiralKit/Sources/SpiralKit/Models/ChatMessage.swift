import Foundation

// MARK: - Chat Message

/// A single message in the coach chat conversation.
/// Stored in SpiralStore for persistence across sessions.
public struct ChatMessage: Codable, Identifiable, Sendable {
    public var id: UUID
    /// Who sent this message.
    public var role: ChatRole
    /// The text content.
    public var content: String
    /// When the message was created.
    public var timestamp: Date
    /// True while the assistant is still streaming tokens.
    public var isStreaming: Bool

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    /// Convenience for creating a user message.
    public static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: text)
    }

    /// Convenience for creating an empty assistant message (used as streaming placeholder).
    public static func assistantStreaming() -> ChatMessage {
        ChatMessage(role: .assistant, content: "", isStreaming: true)
    }
}

// MARK: - Chat Role

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}
