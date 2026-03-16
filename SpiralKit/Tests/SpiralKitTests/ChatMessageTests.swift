import Testing
import Foundation
@testable import SpiralKit

@Suite("ChatMessage")
struct ChatMessageTests {

    // MARK: - Codable

    @Test("ChatMessage round-trips through JSON")
    func testCodableRoundTrip() throws {
        let msg = ChatMessage(
            role: .user,
            content: "How's my sleep?",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(decoded.id == msg.id)
        #expect(decoded.role == .user)
        #expect(decoded.content == "How's my sleep?")
        #expect(decoded.isStreaming == false)
    }

    @Test("ChatMessage array Codable")
    func testArrayCodable() throws {
        let messages: [ChatMessage] = [
            .user("Hello"),
            ChatMessage(role: .assistant, content: "Hi there!"),
            ChatMessage(role: .system, content: "You are a coach.")
        ]

        let data = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].role == .user)
        #expect(decoded[1].role == .assistant)
        #expect(decoded[2].role == .system)
    }

    // MARK: - Convenience Initializers

    @Test("user() convenience creates correct message")
    func testUserConvenience() {
        let msg = ChatMessage.user("Test")
        #expect(msg.role == .user)
        #expect(msg.content == "Test")
        #expect(msg.isStreaming == false)
    }

    @Test("assistantStreaming() creates empty streaming message")
    func testAssistantStreaming() {
        let msg = ChatMessage.assistantStreaming()
        #expect(msg.role == .assistant)
        #expect(msg.content == "")
        #expect(msg.isStreaming == true)
    }

    // MARK: - Identifiable

    @Test("Each ChatMessage has a unique ID")
    func testUniqueIDs() {
        let a = ChatMessage.user("A")
        let b = ChatMessage.user("B")
        #expect(a.id != b.id)
    }
}
