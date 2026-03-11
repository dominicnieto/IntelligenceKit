#if canImport(Observation)
import Testing
@testable import Swarm

@MainActor
@Suite("Conversation")
struct ConversationTests {
    @Test func startsEmpty() {
        let agent = Agent("Be helpful.")
            .provider(MockInferenceProvider(responses: []))
        let conv = Conversation(agent: agent)
        #expect(conv.messages.isEmpty)
        #expect(!conv.isThinking)
        #expect(conv.streamingText.isEmpty)
    }

    @Test func sendAppendsUserAndAssistantMessages() async throws {
        let mock = MockInferenceProvider(responses: ["Hello there!"])
        let conv = Conversation(agent: Agent("Help.").provider(mock))
        try await conv.send("Hi!")
        #expect(conv.messages.count == 2)
        #expect(conv.messages[0].role == .user)
        #expect(conv.messages[0].text == "Hi!")
        #expect(conv.messages[1].role == .assistant)
        #expect(!conv.isThinking)
    }

    @Test func clearRemovesAllMessages() async throws {
        let mock = MockInferenceProvider(responses: ["Reply"])
        let conv = Conversation(agent: Agent("Help.").provider(mock))
        try await conv.send("Hello")
        conv.clear()
        #expect(conv.messages.isEmpty)
    }

    @Test func conversationMessageHasCorrectProperties() {
        let msg = ConversationMessage(role: .user, text: "Hello")
        #expect(msg.role == .user)
        #expect(msg.text == "Hello")
        #expect(!msg.isError)
    }

    @Test func errorMessageAppended() async {
        let mock = MockInferenceProvider(responses: [])
        await mock.setError(AgentError.inferenceProviderUnavailable(reason: "test"))
        let conv = Conversation(agent: Agent("Help.").provider(mock))
        do {
            try await conv.send("Hi!")
        } catch {
            // Expected
        }
        #expect(conv.messages.count == 2)
        #expect(conv.messages[1].isError)
    }
}
#endif
