# V3 API Redesign — Final Push

**Date:** 2026-03-16
**Status:** Approved
**Goal:** Complete the remaining ~15% of V3 API redesign — seal AnyJSONTool, add `#Tool` macro, reduce public type count, validate with AI agent eval.

---

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| AnyJSONTool seal | Full internal — not `@_spi` | Pre-1.0 framework, clean break |
| Inline tools | `#Tool` freestanding expression macro | Compile-time param extraction from closure labels |
| Type reduction | Delete type-erasers, keep concrete public, factory-first | `where Self ==` requires public concrete types |
| Agent init | `init(_:provider:tools:)` + modifier chain | Progressive disclosure, one obvious path |
| Optional subsystems | `some` for singles, `any` for optional/arrays | Swift type system constraint |
| Config vs runtime | Modifiers set defaults, `run()` accepts overrides | Memory/tracer are execution concerns |

---

## 1. Agent — Core Public Surface

### Init + Modifiers

```swift
public struct Agent: AgentRuntime, Sendable {
    // Internal storage — all `any` for existential flexibility
    internal var _instructions: String
    internal var _provider: any InferenceProvider
    internal var _memory: any Memory
    internal var _retryPolicy: any RetryPolicy
    internal var _tracer: (any Tracer)?
    internal var _tools: [any AnyJSONTool]           // internal bridge type
    internal var _inputGuardrails: [any InputGuardrail]
    internal var _outputGuardrails: [any OutputGuardrail]
    internal var _handoffs: [any AgentRuntime]

    // ONE init — instructions + provider (commonly customized) + tools (trailing closure)
    public init(
        _ instructions: String,
        provider: some InferenceProvider = .anthropic(),
        @ToolBuilder tools: () -> [any Tool] = { [] }
    )

    // Progressive disclosure via modifiers — returns modified copy
    public func tools(_ tools: [any Tool]) -> Agent
    public func memory(_ memory: some Memory) -> Agent
    public func retryPolicy(_ policy: some RetryPolicy) -> Agent
    public func tracer(_ tracer: any Tracer) -> Agent
    public func guardrails(
        input: [any InputGuardrail] = [],
        output: [any OutputGuardrail] = []
    ) -> Agent
    public func handoffs(_ agents: [any AgentRuntime]) -> Agent

    // Execution — defaults from modifiers, overrides per-run
    public func run(
        _ input: String,
        memory: (any Memory)? = nil,
        tracer: (any Tracer)? = nil
    ) async throws -> AgentResult

    // Sugar — calls run() with defaults
    public func callAsFunction(_ input: String) async throws -> AgentResult
}
```

### Usage Spectrum

```swift
// Minimal
let agent = Agent("You are helpful")

// Typical
let agent = Agent("You are helpful", provider: .anthropic(apiKey: key)) {
    WeatherTool()
    SearchTool()
}

// Full
let agent = Agent("You are helpful", provider: .anthropic(apiKey: key)) {
    #Tool("greet", "Says hello") { (name: String) in "Hello, \(name)!" }
    WeatherTool()
}
.memory(.slidingWindow(maxTokens: 4000))
.retryPolicy(.exponential(maxRetries: 5))
.tracer(.console())
.guardrails(input: [.notEmpty(), .maxLength(1000)])
.handoffs([triageAgent, researchAgent])

// Execution
let result = try await agent("Hello")                           // callAsFunction
let result = try await agent.run("Hello", memory: .vector(...)) // override memory for this run
```

---

## 2. AnyJSONTool — Internal Seal

### Change

Make `AnyJSONTool` protocol `internal`. All public-facing signatures use `Tool` protocol.

### Bridge Pattern

```swift
// PUBLIC — what users see and conform to
public protocol Tool: Sendable {
    static var toolName: String { get }
    static var toolDescription: String { get }
    func call() async throws -> String
}

// INTERNAL — what talks to LLM providers (JSON schema, raw argument dispatch)
internal protocol AnyJSONTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    func execute(arguments: [String: Any]) async throws -> String
}

// INTERNAL — auto-wraps any Tool into AnyJSONTool for provider calls
internal struct ToolBridge<T: Tool>: AnyJSONTool {
    let tool: T
    var name: String { T.toolName }
    var description: String { T.toolDescription }
    var parameters: [ToolParameter] { /* extracted from @Parameter properties */ }
    func execute(arguments: [String: Any]) async throws -> String {
        // Populate @Parameter properties from arguments, call tool.call()
    }
}
```

### Agent Internals

```swift
public struct Agent {
    internal var _tools: [any AnyJSONTool]   // internal storage

    public init(_ instructions: String, ..., @ToolBuilder tools: () -> [any Tool]) {
        // Bridge each Tool to AnyJSONTool for internal use
        self._tools = tools().map { ToolBridge(tool: $0) }
    }

    public func tools(_ tools: [any Tool]) -> Agent {
        var copy = self
        copy._tools = tools.map { ToolBridge(tool: $0) }
        return copy
    }
}
```

### Files Affected (18)

All files currently exposing `AnyJSONTool` in public signatures:
- `Agent.swift` — stored property type
- `AgentRuntime.swift` — protocol requirement
- `ToolParameterBuilder.swift` — ToolBuilder result type
- `ToolBridging.swift` — adapter visibility
- `AgentTool.swift`, `BuiltInTools.swift`, `FunctionTool.swift` — conformances
- `ObservedAgent.swift`, `EnvironmentAgent.swift` — internal usage
- `MCPClient.swift`, `MCPToolBridge.swift` — MCP bridging
- `ToolGuardrails.swift` — guardrail references
- `HiveSwarm/GraphAgent.swift`, `HiveSwarm/ToolRegistryAdapter.swift` — HiveSwarm
- `MacroDeclarations.swift` — macro declarations
- `SwarmMacros/AgentMacro.swift`, `SwarmMacros/ToolMacro.swift` — macro expansions

---

## 3. `#Tool` Freestanding Expression Macro

### Declaration

```swift
// In MacroDeclarations.swift
@freestanding(expression)
public macro Tool(
    _ name: String,
    _ description: String
) = #externalMacro(module: "SwarmMacros", type: "InlineToolMacro")
```

### Expansion

```swift
// User writes:
#Tool("greet", "Says hello") { (name: String, age: Int) in
    "Hello, \(name)! You are \(age)."
}

// Macro expands to:
{
    struct _InlineTool_greet: Tool, Sendable {
        static let toolName = "greet"
        static let toolDescription = "Says hello"
        @Parameter(description: "name") var name: String
        @Parameter(description: "age") var age: Int
        func call() async throws -> String {
            "Hello, \(name)! You are \(age)."
        }
    }
    return _InlineTool_greet()
}()
```

### Supported Features

- Any number of labeled closure parameters → become `@Parameter` properties
- Optional parameters (`String?`) → non-required in tool schema
- Parameters with defaults → non-required with default value
- `async throws` closure body
- Return type is always `String`
- Works inside `@ToolBuilder` trailing closures

### Implementation

New file: `SwarmMacros/InlineToolMacro.swift`
- Conforms to `ExpressionMacro`
- Uses SwiftSyntax to parse `ClosureExprSyntax` parameter clause
- Extracts parameter labels and type annotations
- Generates anonymous struct conforming to `Tool`
- Wraps in immediately-invoked closure expression

---

## 4. Subsystem Factory Pattern

Applied uniformly to all subsystems. Concrete types stay `public` (required by `where Self ==` pattern) but users reach them through factory dot-syntax.

### Memory

```swift
public protocol Memory: Sendable {
    func store(_ message: Message) async throws
    func recall(limit: Int) async throws -> [Message]
}

// Concrete types — public but accessed via factories
public struct ConversationMemory: Memory { ... }
public struct VectorMemory: Memory { ... }
public struct SlidingWindowMemory: Memory { ... }

// Dot-syntax factories
extension Memory where Self == ConversationMemory {
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory { ... }
}
extension Memory where Self == VectorMemory {
    public static func vector(provider: some EmbeddingProvider) -> VectorMemory { ... }
}
extension Memory where Self == SlidingWindowMemory {
    public static func slidingWindow(maxTokens: Int) -> SlidingWindowMemory { ... }
}
```

### InferenceProvider

```swift
public protocol InferenceProvider: Sendable { ... }

extension InferenceProvider where Self == AnthropicProvider {
    public static func anthropic(apiKey: String, model: String = "claude-sonnet-4-20250514") -> AnthropicProvider { ... }
}
extension InferenceProvider where Self == OpenAIProvider {
    public static func openAI(apiKey: String, model: String = "gpt-4o") -> OpenAIProvider { ... }
}
extension InferenceProvider where Self == OllamaProvider {
    public static func ollama(_ model: String) -> OllamaProvider { ... }
}
```

### Guardrails

```swift
public protocol InputGuardrail: Sendable {
    func validate(_ input: String) async throws -> GuardrailResult
}
public protocol OutputGuardrail: Sendable {
    func validate(_ output: String) async throws -> GuardrailResult
}

// Concrete structs with static factories
public struct InputGuard: InputGuardrail { ... }
public struct OutputGuard: OutputGuardrail { ... }

extension InputGuardrail where Self == InputGuard {
    public static func maxLength(_ n: Int) -> InputGuard { ... }
    public static func notEmpty() -> InputGuard { ... }
    public static func custom(_ name: String, _ check: @Sendable (String) async throws -> GuardrailResult) -> InputGuard { ... }
}
extension OutputGuardrail where Self == OutputGuard {
    public static func maxLength(_ n: Int) -> OutputGuard { ... }
    public static func custom(_ name: String, _ check: @Sendable (String) async throws -> GuardrailResult) -> OutputGuard { ... }
}
```

### Tracer

```swift
public protocol Tracer: Sendable { ... }

extension Tracer where Self == ConsoleTracer {
    public static func console(verbose: Bool = false) -> ConsoleTracer { ... }
}
extension Tracer where Self == SwiftLogTracer {
    public static func swiftLog(label: String = "swarm") -> SwiftLogTracer { ... }
}
```

### RetryPolicy

```swift
public protocol RetryPolicy: Sendable { ... }

extension RetryPolicy where Self == ExponentialBackoff {
    public static func exponential(maxRetries: Int = 3) -> ExponentialBackoff { ... }
}
extension RetryPolicy where Self == LinearBackoff {
    public static func linear(maxRetries: Int = 3, delay: Duration = .seconds(1)) -> LinearBackoff { ... }
}
```

---

## 5. Types to Delete

| Type | Replaced by |
|------|-------------|
| `AnyMemory` | `any Memory` (native Swift existential) |
| `MemoryBuilder` | `some Memory` + constrained extensions |
| `ClosureInputGuardrail` | `InputGuard.custom()` factory |
| `ClosureOutputGuardrail` | `OutputGuard.custom()` factory |
| `AnyTool` | `any Tool` (native Swift existential) |
| `AnyAgent` | `any AgentRuntime` (native Swift existential) |
| `ParallelComposition` | Already deprecated — delete |
| `AgentSequence` | Already deprecated — delete |
| Deprecated `ChatGraph.start(threadID:input:options:)` | Delete |
| Deprecated `ChatGraph.resume(threadID:interruptID:payload:options:)` | Delete |
| Deprecated `Workflow+Durable.execute(resumeFrom:)` | Delete |
| Deprecated `AgentTracer.parallel` parameter | Delete |

---

## 6. ToolBuilder Update

`@ToolBuilder` result builder changes from `[any AnyJSONTool]` to `[any Tool]`:

```swift
@resultBuilder
public struct ToolBuilder {
    public static func buildBlock(_ components: any Tool...) -> [any Tool] {
        components
    }
    public static func buildOptional(_ component: [any Tool]?) -> [any Tool] {
        component ?? []
    }
    public static func buildEither(first component: [any Tool]) -> [any Tool] {
        component
    }
    public static func buildEither(second component: [any Tool]) -> [any Tool] {
        component
    }
    public static func buildArray(_ components: [[any Tool]]) -> [any Tool] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: any Tool) -> [any Tool] {
        [expression]
    }
}
```

---

## 7. Estimated Final Public Type Count

| Category | Types | Count |
|----------|-------|-------|
| Core | `Agent`, `AgentRuntime`, `AgentError`, `AgentEvent`, `AgentResult` | 5 |
| Tools | `Tool` (protocol), `ToolParameter`, `ToolSchema`, `@Tool`, `#Tool`, `@Parameter`, `@ToolBuilder` | 4 types + 3 macros |
| Memory | `Memory` (protocol), `ConversationMemory`, `VectorMemory`, `SlidingWindowMemory`, `PersistentMemory`, `HybridMemory`, `SummaryMemory` | 7 |
| Guardrails | `InputGuardrail`, `OutputGuardrail`, `InputGuard`, `OutputGuard`, `GuardrailResult`, `GuardrailError` | 6 |
| Providers | `InferenceProvider`, `AnthropicProvider`, `OpenAIProvider`, `OllamaProvider`, `GeminiProvider`, `InferenceOptions`, `InferenceResponse`, `LLM` | 8 |
| Observability | `Tracer`, `TraceEvent`, `TraceSpan`, `AgentObserver`, `ConsoleTracer`, `SwiftLogTracer` | 6 |
| Handoffs | `HandoffRequest`, `HandoffResult`, `HandoffConfiguration` | 3 |
| Resilience | `RetryPolicy`, `ExponentialBackoff`, `LinearBackoff`, `CircuitBreaker` | 4 |
| Workflow | `Workflow`, `WorkflowError` | 2 |
| MCP | `MCPClient`, `MCPServer`, `MCPError`, `MCPCapabilities` | 4 |
| Config | `ModelSettings`, `ContextProfile` | 2 |
| HiveSwarm | `HiveSwarm`, `ChatGraph`, `GraphNode` | 3 |
| Errors/Enums | `ToolRegistryError`, `AgentEvent` cases, misc enums | ~10 |
| **Total** | | **~67** |

Down from 197 → **66% reduction**. Each remaining type earns its place.

---

## 8. AI Agent Eval Criteria

After implementation, validate:

1. **Zero-shot creation** — Can an AI agent create a working agent with one prompt, no docs?
2. **Autocomplete path** — Does typing `Agent(` lead to exactly ONE init signature?
3. **Modifier discovery** — Does typing `.` after an Agent show all modifiers?
4. **Tool creation** — Can the agent use both `#Tool` (inline) and `@Tool` (struct) without confusion?
5. **Factory discovery** — Does `.` on `some Memory` show all factory methods?
6. **No AnyJSONTool leakage** — Is `AnyJSONTool` completely invisible in autocomplete/docs?
7. **Simple case simplicity** — Is `Agent("...") { Tool() }` the obvious first thing to try?

Target: **95/100** agent score (measured by success rate across 20 common agent-building prompts).

---

## 9. Migration Notes

- **Breaking change**: `AnyJSONTool` no longer public. Any external code referencing it must switch to `Tool` protocol.
- **Breaking change**: Agent init signature changes. Old multi-param inits removed.
- **Non-breaking**: Modifier methods are additive. Existing `.run()` calls continue to work.
- **Deprecation period**: None — pre-1.0 framework, clean break.
