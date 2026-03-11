import Testing
@testable import Swarm

@Suite("Agent")
struct AgentV3Tests {
    @Test func agentCreatedWithInstructions() {
        let agent = Agent("You are helpful.")
        #expect(agent.instructions == "You are helpful.")
        #expect(agent.tools.isEmpty)
        #expect(agent.name == "agent")
    }

    @Test func agentWithToolsViaBuilder() {
        struct FakeTool: ToolV3 {
            static let name = "fake"
            static let description = "Fake"
            func call() async throws -> String { "" }
            func toAnyJSONTool() -> any AnyJSONTool { fatalError() }
        }
        let agent = Agent("Be helpful.") { FakeTool() }
        #expect(agent.tools.count == 1)
    }

    @Test func modifierChainProducesNewValue() {
        let agent = Agent("Help.")
            .named("assistant")
            .options(.precise)
            .memory(.conversation(limit: 20))
        #expect(agent.name == "assistant")
        #expect(agent.options.temperature == 0.0)
    }

    @Test func modifierChainIsImmutable() {
        let original = Agent("Help.")
        let modified = original.named("modified")
        #expect(original.name == "agent")
        #expect(modified.name == "modified")
    }

    @Test func providerModifier() {
        let agent = Agent("Help.")
            .provider(MockInferenceProvider(responses: []))
        #expect(agent._provider != nil)
    }

    @Test func guardrailsModifier() {
        let agent = Agent("Help.")
            .guardrails(.inputNotEmpty, .maxInput(characters: 100))
        #expect(agent.guardrails.count == 2)
    }

    @Test func handoffsModifier() {
        let specialist = Agent("Specialist.").named("specialist")
        let agent = Agent("Router.").handoffs(specialist)
        #expect(agent.handoffAgents.count == 1)
    }

    @Test func makeRuntimeCreatesAgent() throws {
        let agent = Agent("Be helpful.")
            .named("test-agent")
            .options(.precise)
            .provider(MockInferenceProvider(responses: []))
        let runtime = try agent.makeRuntime()
        #expect(runtime.name == "test-agent")
        #expect(runtime.configuration.temperature == 0.0)
    }

    @Test func agentRunProducesResult() async throws {
        let mock = MockInferenceProvider(responses: ["Hello world"])
        let agent = Agent("Be helpful.").provider(mock)
        let result = try await agent.run("Say hello")
        #expect(result.output.contains("Hello"))
    }
}
