# Swarm Framework - Comprehensive Feature Guide

> A thorough exploration of Swarm's agent architecture, composable APIs, orchestration patterns, and memory system for the Swift AI developer community.

---

## Table of Contents

1. [Agent Architecture](#1-agent-architecture)
2. [Composable APIs & DSL Patterns](#2-composable-apis--dsl-patterns)
3. [Tool System](#3-tool-system)
4. [Memory & State Management](#4-memory--state-management)
5. [Orchestration & Workflows](#5-orchestration--workflows)
6. [LLM Provider Abstraction](#6-llm-provider-abstraction)
7. [Key Design Philosophies](#7-key-design-philosophies)

---

## 1. Agent Architecture

Swarm's agent system is built on a protocol-oriented foundation with `AgentRuntime` as the central abstraction.

### Core Protocol: `AgentRuntime`

```swift
public protocol AgentRuntime: Sendable {
    nonisolated var name: String { get }
    nonisolated var tools: [any AnyJSONTool] { get }
    nonisolated var instructions: String { get }
    nonisolated var configuration: AgentConfiguration { get }
    nonisolated var memory: (any Memory)? { get }
    nonisolated var inferenceProvider: (any InferenceProvider)? { get }
    nonisolated var tracer: (any Tracer)? { get }
    nonisolated var inputGuardrails: [any InputGuardrail] { get }
    nonisolated var outputGuardrails: [any OutputGuardrail] { get }
    nonisolated var handoffs: [AnyHandoffConfiguration] { get }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult
    func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error>
    func cancel() async
}
```

**Key Design Decisions:**
- `nonisolated` properties enable cheap concurrent access without actor hopping
- Full `Sendable` conformance for safe cross-actor передача
- Extension-defaults pattern provides empty implementations for optional properties

### Primary Agent Implementation

The `Agent` struct implements the full tool-calling loop:

```
Input → Guardrails → Build Prompt → LLM Inference → Tool Calls?
        → Execute Tools → Loop OR Return Result → Output Guardrails → Session/Memory Storage
```

### `@AgentActor` Macro

For simpler agents, the macro generates boilerplate:

```swift
@AgentActor(instructions: "You are an echo agent.")
actor MacroEchoAgent {
    func process(_ input: String) async throws -> String {
        "Echo: \(input)"
    }
}
```

**Generates:** All `AgentRuntime` property requirements, `init()`, `run()`, `stream()`, `cancel()`, and a `Builder` class.

### Agent Implementations

| Type | Purpose |
|------|---------|
| `Agent` | Primary struct with full tool-calling loop |
| `@AgentActor` | Macro-generated lightweight actors |
| `GraphAgent` | Hive integration for deterministic execution |
| `ObservedAgent<Wrapped>` | Wrapper adding observability |
| `EnvironmentAgent` | Wrapper applying task-local environment |

### AgentConfiguration

Builder-pattern configuration:

```swift
AgentConfiguration.default
    .name("WeatherBot")
    .maxIterations(20)
    .temperature(0.8)
    .timeout(.seconds(120))
    .contextProfile(.heavy)
```

### Rich Event System

```swift
public enum AgentEvent: Sendable {
    case lifecycle(Lifecycle)      // started, completed, failed, cancelled
    case tool(Tool)                // started, partial, completed, failed
    case output(Output)            // token, chunk, thinking
    case handoff(Handoff)          // requested, started, completed, skipped
    case observation(Observation)   // decision, planUpdated, memoryAccessed
}
```

### Callable Syntax

```swift
let callable = CallableAgent(myAgent)
let result = try await callable("What is 2+2?")
// or
let result = try await myAgent("What is 2+2?")  // via extension
```

---

## 2. Composable APIs & DSL Patterns

Swarm leverages Swift's type system, result builders, and macros for ergonomic API design.

### ToolBuilder for Declarative Tool Registration

```swift
let agent = try Agent("You are helpful.") {
    WeatherTool()
    CalculatorTool()
    if includeDebug {
        DebugTool()
    }
}
```

### Fluent Builder Pattern

```swift
let agent = try Agent.Builder()
    .tools([WeatherTool(), CalculatorTool()])
    .instructions("You are a helpful assistant.")
    .configuration(.default.maxIterations(10))
    .memory(myMemory)
    .handoffs(billingAgent, supportAgent)
    .build()
```

### Handoff Configuration DSL

```swift
let config = HandoffBuilder(to: executorAgent)
    .toolName("execute_task")
    .toolDescription("Execute the planned task")
    .onTransfer { context, data in
        Log.agents.info("Handoff to \(data.targetAgentName)")
    }
    .transform { data in
        var modified = data
        modified.metadata["timestamp"] = .double(Date().timeIntervalSince1970)
        return modified
    }
    .when { context, _ in
        await context.get("ready")?.boolValue ?? false
    }
    .history(.summarized(maxTokens: 500))
    .build()
```

### Modern Handoff Options API

```swift
agent.asHandoff()
    .name("transfer_to_specialist")
    .description("Escalate to human specialist")
    .history(.summarized(maxTokens: 500))
    .policy(.balanced)
    .onTransfer { context, data in /* logging */ }
```

### Guardrail Composition

```swift
let agent = Agent(
    instructions: "You are helpful",
    inputGuardrails: [
        InputGuard.maxLength(5000),
        InputGuard.notEmpty(),
        InputGuard.custom("no_scripts") { input in
            input.contains("<script")
                ? .tripwire(message: "Scripts not allowed")
                : .passed()
        }
    ],
    outputGuardrails: [
        OutputGuard.maxLength(10000)
    ]
)
```

### Agent Modifiers (Functional Setters)

```swift
let agent = try Agent("Be helpful.")
    .withMemory(.conversation(maxMessages: 50))
    .withTracer(myTracer)
    .withGuardrails(input: [InputGuard.notEmpty()], output: [])
    .withHandoffs([specialistAgent])
    .withTools {
        WeatherTool()
        DateTimeTool()
    }
```

### Result Builder Pattern

Mirrors SwiftUI's `@ViewBuilder`:

```swift
@ToolParameterBuilder
var parameters: [ToolParameter] {
    Parameter("location", description: "City name", type: .string)
    Parameter("units", description: "Temperature units", type: .oneOf(["C", "F"]), required: false)
    if includeTimezone {
        Parameter("timezone", description: "Timezone offset", type: .int)
    }
}
```

### Policy Enums with Associated Values

```swift
public enum HandoffHistory: Sendable, Equatable {
    case none
    case nested
    case summarized(maxTokens: Int = 600)
}
```

### Key API Entry Points

| Component | API |
|-----------|-----|
| Agent Creation | `Agent(instructions:configuration:tools:)` or `Agent.Builder()` |
| Tool Creation | `@Tool` macro, `#Tool` expression macro, `FunctionTool` |
| Handoffs | `HandoffBuilder<Target>`, `handoff(to:)` |
| Guardrails | `InputGuard`, `OutputGuard` closure factories |
| Modifiers | `.withMemory()`, `.withTools()`, `.withGuardrails()` |

---

## 3. Tool System

A sophisticated two-protocol design separates type-safe user APIs from flexible framework internals.

### Two-Protocol Architecture

**`AnyJSONTool`** - Dynamic ABI for framework internals:
```swift
public protocol AnyJSONTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    var inputGuardrails: [any ToolInputGuardrail] { get }
    var outputGuardrails: [any ToolOutputGuardrail] { get }
    var executionSemantics: ToolExecutionSemantics { get }
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}
```

**`Tool`** - Typed protocol for users:
```swift
public protocol Tool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Encodable & Sendable
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    func execute(_ input: Input) async throws -> Output
}
```

### `@Tool` Macro

```swift
@Tool("Calculates mathematical expressions")
struct CalculatorTool {
    @Parameter("The mathematical expression to evaluate")
    var expression: String

    @Parameter("Precision", default: 2)
    var precision: Int = 2

    func execute() async throws -> Double {
        return try evaluate(expression, precision: precision)
    }
}
```

**Generates:** `name`, `description`, `parameters`, `Input`/`Output` typealiases, `execute(arguments:)` wrapper.

### Inline Tool with `#Tool`

```swift
let greetTool = #Tool("greet", "Says hello") { (name: String, age: Int) in
    "Hello, \(name)! You are \(age) years old."
}
```

### Parameter Types

| Type | Usage |
|------|-------|
| `.string` | Text input |
| `.int`, `.double` | Numeric input |
| `.bool` | Toggle |
| `.array(elementType:)` | Lists |
| `.object(properties:)` | Nested objects |
| `.oneOf([String])` | Enum-style choices |
| `.any` | Unconstrained |

### Tool Execution Semantics

Tools declare their side-effect profile:

```swift
public struct ToolExecutionSemantics: Codable, Sendable {
    var sideEffectLevel: ToolSideEffectLevel    // .readOnly, .localMutation, .externalMutation
    var retryPolicy: ToolRetryPolicy            // .automatic, .safe, .unsafe, .callerManaged
    var approvalRequirement: ToolApprovalRequirement  // .automatic, .never, .always
    var resultDurability: ToolResultDurability  // .transcriptOnly, .artifactBacked
}
```

### Guardrails

**Input Guardrails:**
```swift
public protocol ToolInputGuardrail: Sendable {
    var name: String { get }
    func validate(_ data: ToolGuardralData) async throws -> GuardrailResult
}
```

**Output Guardrails:**
```swift
public protocol ToolOutputGuardrail: Sendable {
    var name: String { get }
    func validate(_ data: ToolGuardralData, output: SendableValue) async throws -> GuardrailResult
}
```

### Parallel Tool Execution

```swift
let executor = ParallelToolExecutor()
let results = try await executor.executeInParallel(
    calls,
    using: registry,
    agent: myAgent,
    context: nil,
    errorStrategy: .continueOnError  // .failFast, .collectErrors
)
```

### Built-in Tools

| Tool | Purpose |
|------|---------|
| `CalculatorTool` | Math expression evaluation (Apple only) |
| `DateTimeTool` | Current date/time |
| `StringTool` | String operations |
| `SemanticCompactorTool` | Text summarization |

### Tool Registration

```swift
public actor ToolRegistry {
    func register(_ tool: any AnyJSONTool) throws
    func tool(named name: String) -> (any AnyJSONTool)?
    func execute(toolNamed:name: arguments: ...) async throws -> SendableValue
    var schemas: [ToolSchema]  // For LLM providers
}
```

---

## 4. Memory & State Management

A multi-layered, actor-based memory system with pluggable backends.

### Core Memory Protocol

```swift
public protocol Memory: Actor, Sendable {
    var count: Int { get async }
    var isEmpty: Bool { get async }
    func add(_ message: MemoryMessage) async
    func context(for query: String, tokenLimit: Int) async -> String
    func allMessages() async -> [MemoryMessage]
    func clear() async
}
```

### Memory Implementations

| Type | Purpose |
|------|---------|
| `ConversationMemory` | Simple FIFO rolling buffer |
| `SlidingWindowMemory` | Token-aware sliding window |
| `SummaryMemory` | Auto-summarizes old messages |
| `HybridMemory` | Short-term + long-term combination |
| `VectorMemory` | RAG-style semantic search |
| `SwiftDataMemory` | SwiftData-backed persistence |
| `WaxMemory` | Wax knowledge graph integration |

### Session: Conversation History Storage

Separated from memory for clean separation of concerns:

```swift
public protocol Session: Actor, Sendable {
    nonisolated var sessionId: String { get }
    func getItems(limit: Int?) async throws -> [MemoryMessage]
    func addItems(_ items: [MemoryMessage]) async throws
    func popItem() async throws -> MemoryMessage?
}
```

### EmbeddingProvider for Semantic Search

```swift
public protocol EmbeddingProvider: Sendable {
    var dimensions: Int { get }
    var modelIdentifier: String { get }
    func embed(_ text: String) async throws -> [Float]
    func embedQuery(_ query: String) async throws -> [Float]
}
```

### Memory Attachment to Agents

```swift
// Direct
let agent = Agent(
    memory: .conversation(maxMessages: 100),
    instructions: "You are helpful."
)

// Builder
let agent = Agent.Builder()
    .memory(.vector(embeddingProvider: myProvider))
    .build()

// Fluent modifier
let agent = try Agent("Be helpful.")
    .withMemory(.slidingWindow(maxTokens: 4000))
```

### Context Budgeting

```swift
public struct ContextProfile: Sendable, Equatable {
    public var memoryTokenLimit: Int       // Max tokens for memory retrieval
    public var maxRetrievedItems: Int       // Maximum items to retrieve (2-5)
    public var maxRetrievedItemTokens: Int  // Max tokens per item (300-500)
    public var summaryTokenRatio: Double    // Portion for summaries (40-60%)
}
```

| Preset | Memory Token Ratio | Purpose |
|--------|-------------------|---------|
| **lite** | 35% | Low-latency, mobile-first |
| **balanced** | 30% | General-purpose (default) |
| **heavy** | 25% | Deep research, multi-step |

### Wax Integration

```swift
public actor WaxMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle {
    public init(
        url: URL,
        embedder: (any WaxVectorSearch.EmbeddingProvider)? = nil,
        configuration: Configuration = .default
    ) async throws
}
```

### Key Architecture

- **Actor isolation** for thread-safe concurrent access
- **Two-store design**: Session = conversation storage, Memory = context retrieval
- **Session seeding**: Memory can ingest session history on first use
- **Pluggable backends**: SwiftData, custom persistence

---

## 5. Orchestration & Workflows

Multi-agent execution with fluent API and durable checkpoint support.

### Workflow Composition

```swift
let result = try await Workflow()
    .step(researchAgent)          // Executes first
    .step(writeAgent)             // Receives research output as input
    .run("Research topic")
```

### Step Types

```swift
enum Step: @unchecked Sendable {
    case single(any AgentRuntime)                    // Sequential
    case parallel([any AgentRuntime], merge: MergeStrategy)  // Concurrent
    case route(@Sendable (String) -> (any AgentRuntime)?)   // Dynamic routing
    case fallback(primary: any AgentRuntime, backup: any AgentRuntime, retries: Int)
}
```

### Parallel Execution with Merging

```swift
let result = try await Workflow()
    .parallel([bullAgent, bearAgent], merge: .structured)
    .run("Analyze market sentiment")
```

Merge strategies:
- `.structured` - JSON: `{"0": "output0", "1": "output1"}`
- `.indexed` - `[0]: output0\n[1]: output1`
- `.first` - First completed result
- `.custom(closure)` - Custom merger function

### Dynamic Routing

```swift
let result = try await Workflow()
    .route { input in
        input.contains("weather") ? weatherAgent : generalAgent
    }
    .run("What's the weather?")
```

### Repeating Workflows

```swift
let result = try await Workflow()
    .step(iterativeRefiner)
    .repeatUntil(maxIterations: 10) { result in
        result.output.contains("FINAL") || result.iterationCount >= 5
    }
    .run("Improve this text")
```

### Durable Execution with HiveCore

```swift
let result = try await Workflow()
    .step(agentA)
    .step(agentB)
    .durable
    .checkpoint(id: "workflow-123", policy: .onCompletion)
    .checkpointing(.fileSystem(directory: checkpointDir))
    .execute("input", resumeFrom: "workflow-123")
```

Checkpoint policies:
- `.onCompletion` - Only save when workflow finishes
- `.everyStep` - Save state after each step

### Resilience Patterns

**RetryPolicy:**
```swift
let policy = RetryPolicy(
    maxAttempts: 3,
    backoff: .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0)
)
```

**CircuitBreaker:**
```swift
let breaker = CircuitBreaker(
    name: "payment-service",
    failureThreshold: 5,
    resetTimeout: 60.0
)
```

**FallbackChain:**
```swift
let result = try await FallbackChain<String>()
    .attempt(name: "Primary") { try await primaryService.fetch() }
    .attempt(name: "Secondary") { try await secondaryService.fetch() }
    .fallback(name: "Cache") { cachedValue }
    .execute()
```

### Error Handling

```swift
enum WorkflowError: Error {
    case agentNotFound(name: String)
    case handoffFailed(source: String, target: String, reason: String)
    case routingFailed(reason: String)
    case mergeStrategyFailed(reason: String)
    case allAgentsFailed(errors: [String])
    case workflowInterrupted(reason: String)
    case checkpointStoreRequired
    case resumeDefinitionMismatch(reason: String)
}
```

---

## 6. LLM Provider Abstraction

Layered architecture with Conduit as the core transport, wrapped by Swarm abstractions.

### Provider Hierarchy

```
InferenceProvider (base contract)
    ├── ToolCallStreamingInferenceProvider
    ├── ConversationInferenceProvider
    │       ├── StreamingConversationInferenceProvider
    │       └── ToolCallStreamingConversationConversationProvider
    ├── CapabilityReportingInferenceProvider
    └── StructuredOutputInferenceProvider
```

### High-Level API: `LLM`

```swift
// OpenAI
let llm = LLM.openAI(apiKey: key, model: "gpt-4")

// Anthropic
let llm = LLM.anthropic(apiKey: key, model: "claude-3-5-sonnet")

// OpenRouter with routing
let llm = LLM.openRouter(apiKey: key, model: "anthropic/claude-3.5-sonnet") { routing in
    routing.providers = [.anthropic, .google]
    routing.routeByLatency = true
}

// Ollama (local)
let llm = LLM.ollama(model: "mistral")
```

### Minimal API: `ConduitProviderSelection`

```swift
let provider: any InferenceProvider = .anthropic(apiKey: key, model: "claude-3-5-sonnet")
```

### Supported Providers

| Provider | Configuration |
|----------|---------------|
| OpenAI | API key + model ID |
| Anthropic | API key + model ID |
| OpenRouter | API key + routing options |
| Ollama | host/port (default localhost:11434) |
| MiniMax | Via OpenRouter or native |
| Apple Foundation Models | On-device fallback (macOS 26.0+) |

### OpenRouter Routing

```swift
public struct OpenRouterRouting: Sendable, Hashable {
    var providers: [OpenRouterProvider]?      // [.anthropic, .google]
    var fallbacks: Bool                      // Enable fallback models
    var routeByLatency: Bool
    var siteURL: URL?
    var appName: String?
}
```

### MultiProvider for Runtime Selection

```swift
public actor MultiProvider: InferenceProvider, ConversationInferenceProvider {
    // Model format: "prefix/model-name"
    // "anthropic/claude-3-5-sonnet" -> routes to anthropic
    // "gpt-4" (no prefix) -> uses default

    func register(prefix: String, provider: any InferenceProvider)
    func resolveProvider(for model: String?) -> any InferenceProvider
}
```

### Request Options Mapping

```swift
options.temperature       -> config.temperature(Float)
options.maxTokens         -> config.maxTokens
options.topP               -> config.topP(Float)
options.frequencyPenalty  -> config.frequencyPenalty(Float)
options.stopSequences     -> config.stopSequences
options.parallelToolCalls -> config.parallelToolCalls
options.structuredOutput  -> config.responseFormat(.jsonObject/.jsonSchema)
```

### Adding a New Provider

1. Add factory method to `LLM.Kind` enum
2. Implement `makeProvider()` case
3. Add dot-syntax extension on `InferenceProvider`
4. (Optional) Add to `OpenRouterProvider` enum for OpenRouter routing

---

## 7. Key Design Philosophies

### Protocol-Oriented Design

- `AgentRuntime` as the central abstraction
- Default implementations via protocol extensions
- Type erasure for collections (`AnyHandoffConfiguration`, `ToolCollection`)

### Composition Over Inheritance

Agents compose tools, guardrails, handoffs, memory, and tracers rather than subclassing.

### Actor Isolation for Thread Safety

Memory, ToolRegistry, CircuitBreaker, and workflow engines use Swift actors for safe concurrent access.

### Immutable Value Types

Builders return new copies rather than mutating:
```swift
public func toolName(_ name: String) -> HandoffBuilder<Target> {
    var copy = self
    copy.toolNameOverride = name
    return copy
}
```

### Swift 6 Concurrency Ready

- Full `Sendable` conformance on core types
- `nonisolated` property accessors where safe
- Actor isolation for mutable state

### Result Builders for DSL

Mirrors SwiftUI's `@ViewBuilder`:
- `buildBlock` for multiple expressions
- `buildOptional` for `if` statements
- `buildEither` for `if`/`else`
- `buildArray` for loops

### Separation of Concerns

- **Session**: Conversation history storage
- **Memory**: Context retrieval (RAG, summaries)
- **AgentRuntime**: Tool orchestration
- **Workflow**: Multi-agent orchestration

### First-Class Swift citizen

- Native Swift concurrency (`async/await`, `AsyncThrowingStream`)
- Swift macros (`@Tool`, `@AgentActor`, `@Builder`)
- Swift protocol system
- Natural Swift API patterns

---

## Quick Reference: Creating a Swarm Agent

```swift
import Swarm

// 1. Define a tool
@Tool("Fetches weather for a location")
struct WeatherTool {
    @Parameter("City name")
    var city: String

    @Parameter("Units", oneOf: ["celsius", "fahrenheit"])
    var units: String = "fahrenheit"

    func execute() async throws -> String {
        let temp = try await fetchWeather(city: city, units: units)
        return "\(temp)° in \(city)"
    }
}

// 2. Create an agent
let agent = try Agent(
    instructions: "You are a helpful weather assistant.",
    tools: [WeatherTool()]
)

// 3. Run the agent
let result = try await agent("What's the weather in NYC?")

// 4. Or compose workflows
let result = try await Workflow()
    .step(weatherAgent)
    .step(notificationAgent)
    .run("Weather alert for NYC")
```

---

*Document generated from Swarm framework source analysis. For the latest updates, check the [Swarm repository](https://github.com/anthropics/swarm).*
