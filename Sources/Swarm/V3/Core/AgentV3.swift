import Foundation

/// THE agent type for V3 API. Struct (value type), ONE init, modifier chain.
///
/// ```swift
/// let agent = Agent("You are a helpful assistant.") {
///     SearchTool()
///     CalculatorTool()
/// }
/// .named("assistant")
/// .options(.precise)
/// .memory(.conversation(limit: 50))
/// .provider(myProvider)
/// ```
public struct Agent: Sendable {
    public let instructions: String
    public let tools: [any ToolV3]
    public let name: String
    public let options: RunOptions
    public let memoryOption: MemoryOption
    public let guardrails: [GuardrailSpec]
    public let handoffAgents: [Agent]
    let _provider: (any InferenceProvider)?

    /// Create an agent. This is the ONLY public init.
    public init(
        _ instructions: String,
        @ToolBuilder tools: () -> [any ToolV3] = { [] }
    ) {
        self.instructions = instructions
        self.tools = tools()
        self.name = "agent"
        self.options = .default
        self.memoryOption = .none
        self.guardrails = []
        self.handoffAgents = []
        self._provider = nil
    }

    // Internal memberwise init for modifier chain
    init(
        instructions: String,
        tools: [any ToolV3],
        name: String,
        options: RunOptions,
        memoryOption: MemoryOption,
        guardrails: [GuardrailSpec],
        handoffAgents: [Agent],
        provider: (any InferenceProvider)?
    ) {
        self.instructions = instructions
        self.tools = tools
        self.name = name
        self.options = options
        self.memoryOption = memoryOption
        self.guardrails = guardrails
        self.handoffAgents = handoffAgents
        self._provider = provider
    }
}

// MARK: - Modifier Chain

extension Agent {
    public func named(_ name: String) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memoryOption, guardrails: guardrails,
            handoffAgents: handoffAgents, provider: _provider
        )
    }

    public func options(_ options: RunOptions) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memoryOption, guardrails: guardrails,
            handoffAgents: handoffAgents, provider: _provider
        )
    }

    public func memory(_ memory: MemoryOption) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memory, guardrails: guardrails,
            handoffAgents: handoffAgents, provider: _provider
        )
    }

    public func guardrails(_ guardrails: GuardrailSpec...) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memoryOption, guardrails: guardrails,
            handoffAgents: handoffAgents, provider: _provider
        )
    }

    public func handoffs(_ agents: Agent...) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memoryOption, guardrails: guardrails,
            handoffAgents: agents, provider: _provider
        )
    }

    public func provider(_ provider: some InferenceProvider) -> Agent {
        Agent(
            instructions: instructions, tools: tools, name: name,
            options: options, memoryOption: memoryOption, guardrails: guardrails,
            handoffAgents: handoffAgents, provider: provider
        )
    }
}

// MARK: - Execution (Bridge to existing LegacyAgent actor)

extension Agent {
    /// Run the agent with the given input. Returns the final result.
    public func run(_ input: String) async throws -> AgentResult {
        let runtime = try makeRuntime()
        return try await runtime.run(input)
    }

    /// Stream agent events as they occur.
    public func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
        guard let runtime = try? makeRuntime() else {
            return AsyncThrowingStream { $0.finish(throwing: AgentError.internalError(reason: "Failed to create runtime")) }
        }
        return runtime.stream(input)
    }

    /// Bridge: creates an internal `LegacyAgent` actor from V3 config.
    /// This is the temporary bridge — replaced in Phase 11 when Agent becomes canonical.
    func makeRuntime() throws -> LegacyAgent {
        let config = AgentConfiguration(
            name: name,
            maxIterations: options.maxIterations,
            temperature: options.temperature,
            maxTokens: options.maxTokens
        )

        return try LegacyAgent(
            tools: tools.map { $0.toAnyJSONTool() },
            instructions: instructions,
            configuration: config,
            memory: memoryOption.makeMemory(),
            inferenceProvider: _provider
        )
    }
}
