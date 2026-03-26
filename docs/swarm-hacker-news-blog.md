# Why Swift is a Surprisingly Good Language for Coding Agents

Claude Code and Codex proved coding agents work. Both are built on Python or TypeScript under the hood — the standard choice for AI tools.

But I've been building Swarm, a multi-agent framework in Swift, and I keep running into reasons why Swift is actually better suited for this domain than the conventional wisdom suggests.

Here's the case.

## The concurrency problem nobody talks about

Coding agents run multiple tools concurrently, manage long-running sessions, and handle streaming responses — all simultaneously. In Python or TypeScript, this means managing async state, locks, or callbacks. Get it wrong and you get data races or deadlock.

Swift handles this with **actors** — the compiler enforces that only one task can access mutable state at a time.

```swift
public actor ToolRegistry {
    private var tools: [String: any AnyJSONTool] = [:]

    func register(_ tool: any AnyJSONTool) throws {
        guard tools[tool.name] == nil else {
            throw ToolRegistryError.duplicateToolName(name: tool.name)
        }
        tools[tool.name] = tool
    }

    func execute(toolNamed name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let tool = tools[name] else {
            throw AgentError.toolNotFound(name: name)
        }
        return try await tool.execute(arguments: arguments)
    }
}
```

The compiler knows `ToolRegistry` is thread-safe. You can't accidentally share it across tasks without `await`. Data races become compile errors, not production bugs.

## Type-safe tools — no more dictionary soup

In Python or TypeScript, tools typically receive dictionaries. You validate at runtime, or write separate schema files.

Swift's `SendableValue` is a type-safe alternative to `[String: Any]` that you can pass across concurrency boundaries:

```swift
public enum SendableValue: Sendable, Equatable, Hashable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([SendableValue])
    case dictionary([String: SendableValue])
}
```

And it conforms to `ExpressibleBy*Literal` — you write nested JSON-like structures in Swift syntax:

```swift
let json: SendableValue = [
    "user": ["name": "Alice", "age": 30],
    "active": true,
    "scores": [95.5, 87.2]
]

let user: UserInfo = try json.decode()
```

This means tool arguments are checked at compile time for JSON serialization, and decoded to typed structs at the call site.

## Macros that eliminate boilerplate

Defining tools in most frameworks means writing schema objects, validation logic, and wrapper code. Swift macros generate this at compile time.

```swift
@Tool("Fetches weather for a location")
struct WeatherTool {
    @Parameter("City name")
    var city: String

    @Parameter("Units", oneOf: ["celsius", "fahrenheit"])
    var units: String = "fahrenheit"

    func execute() async throws -> String {
        let temp = try await weatherAPI.fetch(city: city, units: units)
        return "\(temp)°"
    }
}
```

The macro generates:
- `name` and `description` properties
- The `parameters` array from `@Parameter` annotations
- A `Codable` `Input` struct
- `execute(arguments:)` wrapper
- `Tool` and `Sendable` conformances

You write the business logic. The framework generates the glue.

For one-off tools, there's `#Tool` — a freestanding expression macro:

```swift
let greet = #Tool("greet", "Says hello") { (name: String, age: Int) in
    "Hello, \(name)! You are \(age)."
}
```

## Protocol composition over inheritance

Claude Code and Codex use inheritance or class-based composition. Swift's protocols let you compose behavior without inheritance hierarchies.

```swift
public protocol AgentRuntime: Sendable {
    nonisolated var name: String { get }
    nonisolated var tools: [any AnyJSONTool] { get }
    nonisolated var instructions: String { get }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult
    func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error>
}
```

`Agent` is the main implementation. `@AgentActor` generates lightweight agents from simple functions. `GraphAgent` bridges Hive workflows. `ObservedAgent` wraps any agent with observability — without subclassing any of them.

```swift
// Wrap any agent with logging
let observed = ObservedAgent(wrapped: agent, observer: myObserver)

// AgentActor generates from a simple function
@AgentActor(instructions: "You are a coding assistant")
actor CodeAssistant {
    func process(_ input: String) async throws -> String {
        // ...
    }
}
```

## Phantom types catch bugs at compile time

Agent context often uses string-keyed dictionaries. Swift's phantom types make these compile-time safe:

```swift
extension ContextKey where Value == String {
    static let userID = ContextKey("user_id")
    static let sessionID = ContextKey("session_id")
}

extension ContextKey where Value == Bool {
    static let isAuthenticated = ContextKey("is_authenticated")
}

// Can't set a Bool for userID — compiler error
await context.setTyped(.userID, value: "user-123")
let isAuth: Bool? = await context.getTyped(.isAuthenticated)
```

Set a string for a bool key, and the compiler refuses to compile. No runtime validation needed.

## On-device inference with Apple Silicon

Python AI frameworks need cloud APIs or勉强 run locally. Swift integrates with Apple's on-device AI stack:

```swift
// Uses Apple Neural Engine via Foundation Models when available
let llm = LLM.appleFoundationModels()

// Or OpenRouter for cloud models with routing
let llm = LLM.openRouter(apiKey: key, model: "anthropic/claude-3.5-sonnet") {
    $0.providers = [.anthropic, .google]
    $0.routeByLatency = true
}
```

Built-in tools like `SemanticCompactorTool` use on-device Foundation Models for summarization — no network required.

## Sendable — the concurrency contract

Swift 6 introduces strict concurrency checking. Types must opt into being shared across tasks by conforming to `Sendable`.

Swarm's core types are all `Sendable`:

```swift
public struct AgentResult: Sendable {
    public let output: String
    public let toolCalls: [ToolCall]
    public let iterationCount: Int
    public let duration: Duration
    public let tokenUsage: TokenUsage?
}
```

This means you can pass agent results across task boundaries with the compiler verifying safety. No locks, no shared mutable state, no guesswork.

## The workflow model

All this combines into a compositional workflow system:

```swift
let result = try await Workflow()
    .step(researchAgent)              // Sequential
    .step(writeAgent)                // Gets research output
    .parallel([bullAgent, bearAgent], merge: .structured)
    .repeatUntil(maxIterations: 10) { result in
        result.output.contains("FINAL")
    }
    .run("Climate analysis")
```

Agents are small, focused, testable. Workflows compose them. The actor model keeps state safe as things run concurrently.

## What this means in practice

Python and TypeScript work for AI agents because the ecosystem is mature and the tooling is there.

Swift offers something different:

- **Compile-time concurrency safety** — data races are impossible, not just unlikely
- **Protocol composition** — agents are Lego blocks, not inheritance chains
- **Macros** — less boilerplate, fewer opportunities for mistakes
- **Type safety** — tool schemas, context keys, message types all checked at compile time
- **On-device inference** — run models on Apple Silicon without cloud dependencies

For building AI tools that feel like native applications rather than Python scripts with a UI, Swift is worth a serious look.

## The code

```swift
import Swarm

@Tool("Echoes input back")
struct EchoTool {
    @Parameter("Text to echo")
    var text: String

    func execute() async throws -> String { text }
}

let agent = try Agent("You are helpful.") { EchoTool() }
let result = try await agent("Hello, Swarm!")
```


https://github.com/christopherkarani/Swarm
