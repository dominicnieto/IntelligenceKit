import Testing
@testable import Swarm

@Suite("HandoffTool")
struct HandoffToolTests {
    @Test func handoffNameDerivedFromTarget() {
        let specialist = Agent("Specialist.").named("code-expert")
        let handoff = Handoff(specialist)
        #expect(handoff.instanceName == "handoff_to_code_expert")
    }

    @Test func handoffNameWithSpaces() {
        let agent = Agent("Help.").named("billing support")
        let handoff = Handoff(agent)
        #expect(handoff.instanceName == "handoff_to_billing_support")
    }

    @Test func handoffInToolBuilderIsCountedAsTool() {
        let specialist = Agent("Specialist.").named("specialist")
        let agent = Agent("Coordinator.") { Handoff(specialist) }
        #expect(agent.tools.count == 1)
    }

    @Test func handoffBridgesToAnyJSONTool() {
        let specialist = Agent("Specialist.").named("specialist")
        let handoff = Handoff(specialist)
        let jsonTool = handoff.toAnyJSONTool()
        #expect(jsonTool.name == "handoff_to_specialist")
        #expect(jsonTool.parameters.isEmpty)
    }

    @Test func handoffCustomDescription() {
        let agent = Agent("Help.").named("billing")
        let handoff = Handoff(agent, description: "Route billing questions")
        #expect(handoff.handoffDescription == "Route billing questions")
    }

    @Test func handoffDefaultDescription() {
        let agent = Agent("Help.").named("billing")
        let handoff = Handoff(agent)
        #expect(handoff.handoffDescription == "Transfer to billing")
    }
}
