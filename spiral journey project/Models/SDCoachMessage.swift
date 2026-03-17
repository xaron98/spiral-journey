import Foundation
import SwiftData
import SpiralKit

// MARK: - SDCoachMessage

/// SwiftData model mirroring SpiralKit.ChatMessage.
@Model
final class SDCoachMessage {

    // MARK: Persisted Properties

    @Attribute(.unique) var messageID: UUID
    /// Stored as ChatRole.rawValue ("system" | "user" | "assistant").
    var role: String
    var content: String
    var timestamp: Date
    var isStreaming: Bool

    // MARK: Init

    init(
        messageID: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.messageID = messageID
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    // MARK: Converters

    /// Create an SDCoachMessage from a SpiralKit ChatMessage.
    convenience init(from message: ChatMessage) {
        self.init(
            messageID: message.id,
            role: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            isStreaming: message.isStreaming
        )
    }

    /// Convert back to a SpiralKit ChatMessage.
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: messageID,
            role: ChatRole(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp,
            isStreaming: isStreaming
        )
    }
}
