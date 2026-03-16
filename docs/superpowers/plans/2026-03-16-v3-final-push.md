# V3 API Final Push — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the V3 API redesign — seal AnyJSONTool, add `#Tool` macro, implement modifier-pattern Agent init, reduce public type count from 197 to ~70.

**Architecture:** Internal `AnyJSONTool` protocol hidden behind public `Tool` protocol + `ToolCollection` opaque wrapper. Agent uses single canonical init with progressive disclosure via modifier chain. All subsystems use protocol + constrained `where Self ==` factory extensions for dot-syntax.

**Tech Stack:** Swift 6.2, SwiftSyntax (macros), Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-16-v3-final-push-design.md`

**Branch:** `v3-final-push`

---

## Pre-flight

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b v3-final-push
```

- [ ] **Step 2: Verify clean build baseline**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -10
```

Record pass/fail counts as baseline.

---

## Chunk 1: ToolCollection + Bridge Helper (Foundation)

These are new files with no existing dependencies. Safe to create first.

### Task 1.1: Create ToolCollection struct

**Files:**
- Create: `Sources/Swarm/Tools/ToolCollection.swift`
- Test: `Tests/SwarmTests/V3/ToolCollectionTests.swift`

- [ ] **Step 1: Write failing test for ToolCollection**

```swift
// Tests/SwarmTests/V3/ToolCollectionTests.swift
import Testing
@testable import Swarm

@Suite("ToolCollection")
struct ToolCollectionTests {
    @Test("empty collection has zero storage")
    func emptyCollection() {
        let collection = ToolCollection.empty
        #expect(collection.storage.isEmpty)
    }

    @Test("ToolCollection is Sendable")
    func sendable() {
        let collection = ToolCollection.empty
        let _: any Sendable = collection  // compile-time check
        #expect(collection.storage.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ToolCollectionTests 2>&1 | tail -5
```
Expected: FAIL — `ToolCollection` not defined.

- [ ] **Step 3: Implement ToolCollection**

```swift
// Sources/Swarm/Tools/ToolCollection.swift
import Foundation

/// An opaque collection of tools built by `@ToolBuilder`.
///
/// You never create this directly — it's produced by the `@ToolBuilder` result builder
/// and consumed by `Agent` initializers and modifiers.
public struct ToolCollection: Sendable {
    internal let storage: [any AnyJSONTool]

    /// An empty tool collection.
    public static let empty = ToolCollection(storage: [])

    internal init(storage: [any AnyJSONTool]) {
        self.storage = storage
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ToolCollectionTests 2>&1 | tail -5
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Swarm/Tools/ToolCollection.swift Tests/SwarmTests/V3/ToolCollectionTests.swift
git commit -m "feat: add ToolCollection opaque wrapper for @ToolBuilder"
```

### Task 1.2: Add internal bridge helper

**Files:**
- Create: `Sources/Swarm/Tools/ToolBridgeHelper.swift`
- Test: `Tests/SwarmTests/V3/ToolBridgeHelperTests.swift`

- [ ] **Step 1: Write failing test for bridgeToolToAnyJSON**

```swift
// Tests/SwarmTests/V3/ToolBridgeHelperTests.swift
import Testing
@testable import Swarm

struct MockBridgeTool: Tool {
    typealias Input = MockInput
    typealias Output = String

    struct MockInput: Codable, Sendable {
        let value: String
    }

    let name = "mock_bridge"
    let description = "A mock tool for bridge testing"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "value", description: "test value", type: .string)
    ]

    func execute(_ input: MockInput) async throws -> String {
        "bridged: \(input.value)"
    }
}

@Suite("ToolBridgeHelper")
struct ToolBridgeHelperTests {
    @Test("bridges concrete Tool to AnyJSONTool")
    func bridgeConcreteTool() async throws {
        let tool = MockBridgeTool()
        let bridged = bridgeToolToAnyJSON(tool)
        #expect(bridged.name == "mock_bridge")
        #expect(bridged.description == "A mock tool for bridge testing")
    }

    @Test("bridges any Tool existential to AnyJSONTool via existential opening")
    func bridgeExistential() async throws {
        let tool: any Tool = MockBridgeTool()
        let bridged = bridgeToolToAnyJSON(tool)
        #expect(bridged.name == "mock_bridge")
    }

    @Test("bridged tool executes correctly")
    func bridgedExecution() async throws {
        let tool = MockBridgeTool()
        let bridged = bridgeToolToAnyJSON(tool)
        let result = try await bridged.execute(arguments: ["value": .string("hello")])
        #expect(result == .string("bridged: hello"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter ToolBridgeHelperTests 2>&1 | tail -5
```
Expected: FAIL — `bridgeToolToAnyJSON` not defined.

- [ ] **Step 3: Implement bridge helper**

```swift
// Sources/Swarm/Tools/ToolBridgeHelper.swift
import Foundation

/// Opens a `any Tool` existential and bridges it to the internal `AnyJSONTool` protocol.
///
/// Uses Swift 5.7+ existential opening: when `any Tool` is passed to a generic `<T: Tool>`,
/// the compiler infers `T` as the underlying concrete type.
internal func bridgeToolToAnyJSON<T: Tool>(_ tool: T) -> any AnyJSONTool {
    AnyJSONToolAdapter(tool)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter ToolBridgeHelperTests 2>&1 | tail -5
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Swarm/Tools/ToolBridgeHelper.swift Tests/SwarmTests/V3/ToolBridgeHelperTests.swift
git commit -m "feat: add bridgeToolToAnyJSON helper for existential opening"
```

---

## Chunk 2: ToolBuilder → ToolCollection

Replace the existing `ToolBuilder` result builder to produce `ToolCollection` instead of `[any AnyJSONTool]`.

### Task 2.1: Write new ToolBuilder producing ToolCollection

**Files:**
- Modify: `Sources/Swarm/Tools/ToolParameterBuilder.swift` (lines 252-308, the ToolBuilder struct)
- Test: `Tests/SwarmTests/V3/ToolBuilderV3Tests.swift`

- [ ] **Step 1: Write failing tests for new ToolBuilder**

```swift
// Tests/SwarmTests/V3/ToolBuilderV3Tests.swift
import Testing
@testable import Swarm

// Reuse MockBridgeTool from ToolBridgeHelperTests or define locally

struct ToolBuilderTestTool: Tool {
    typealias Input = ToolBuilderTestInput
    typealias Output = String
    struct ToolBuilderTestInput: Codable, Sendable { let x: String }
    let name: String
    let description = "test"
    let parameters: [ToolParameter] = []
    func execute(_ input: ToolBuilderTestInput) async throws -> String { "ok" }
}

@Suite("ToolBuilder V3")
struct ToolBuilderV3Tests {
    @Test("builds empty ToolCollection")
    func emptyBuilder() {
        @ToolBuilder func build() -> ToolCollection { }
        let collection = build()
        #expect(collection.storage.isEmpty)
    }

    @Test("builds single Tool into ToolCollection")
    func singleTool() {
        @ToolBuilder func build() -> ToolCollection {
            ToolBuilderTestTool(name: "a")
        }
        let collection = build()
        #expect(collection.storage.count == 1)
        #expect(collection.storage[0].name == "a")
    }

    @Test("builds multiple Tools into ToolCollection")
    func multipleTools() {
        @ToolBuilder func build() -> ToolCollection {
            ToolBuilderTestTool(name: "a")
            ToolBuilderTestTool(name: "b")
        }
        let collection = build()
        #expect(collection.storage.count == 2)
    }

    @Test("supports conditional tools")
    func conditionalTool() {
        let includeB = true
        @ToolBuilder func build() -> ToolCollection {
            ToolBuilderTestTool(name: "a")
            if includeB {
                ToolBuilderTestTool(name: "b")
            }
        }
        let collection = build()
        #expect(collection.storage.count == 2)
    }

    @Test("supports any Tool existential in builder")
    func existentialTool() {
        let tool: any Tool = ToolBuilderTestTool(name: "existential")
        @ToolBuilder func build() -> ToolCollection {
            tool
        }
        let collection = build()
        #expect(collection.storage.count == 1)
        #expect(collection.storage[0].name == "existential")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ToolBuilderV3Tests" 2>&1 | tail -10
```
Expected: FAIL — ToolBuilder returns `[any AnyJSONTool]`, not `ToolCollection`.

- [ ] **Step 3: Rewrite ToolBuilder in ToolParameterBuilder.swift**

Replace lines 252-308 of `Sources/Swarm/Tools/ToolParameterBuilder.swift` (the `ToolBuilder` struct) with:

```swift
@resultBuilder
public struct ToolBuilder {
    /// Builds an empty tool collection.
    public static func buildBlock() -> ToolCollection {
        .empty
    }

    /// Builds a tool collection from multiple sub-collections.
    public static func buildBlock(_ components: ToolCollection...) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    /// Converts a typed Tool to a ToolCollection (generic — preserves concrete type).
    public static func buildExpression<T: Tool>(_ expression: T) -> ToolCollection {
        ToolCollection(storage: [AnyJSONToolAdapter(expression)])
    }

    /// Converts an existential `any Tool` to a ToolCollection (uses existential opening).
    public static func buildExpression(_ expression: any Tool) -> ToolCollection {
        ToolCollection(storage: [bridgeToolToAnyJSON(expression)])
    }

    /// Converts a single AnyJSONTool to a ToolCollection (internal — framework built-in tools).
    internal static func buildExpression(_ expression: any AnyJSONTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    /// Converts an array of AnyJSONTools (internal — framework use).
    internal static func buildExpression(_ expression: [any AnyJSONTool]) -> ToolCollection {
        ToolCollection(storage: expression)
    }

    /// Converts an array of Tools.
    public static func buildExpression(_ expression: [any Tool]) -> ToolCollection {
        ToolCollection(storage: expression.map { bridgeToolToAnyJSON($0) })
    }

    /// Optional support (if-let, if without else).
    public static func buildOptional(_ component: ToolCollection?) -> ToolCollection {
        component ?? .empty
    }

    /// if-else first branch.
    public static func buildEither(first component: ToolCollection) -> ToolCollection {
        component
    }

    /// if-else second branch.
    public static func buildEither(second component: ToolCollection) -> ToolCollection {
        component
    }

    /// for-in loop support.
    public static func buildArray(_ components: [ToolCollection]) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    /// #available support.
    public static func buildLimitedAvailability(_ component: ToolCollection) -> ToolCollection {
        component
    }
}
```

- [ ] **Step 4: Run new tests to verify they pass**

```bash
swift test --filter "ToolBuilderV3Tests" 2>&1 | tail -10
```
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
swift test 2>&1 | tail -20
```
Expected: Many failures — existing code uses `[any AnyJSONTool]` return type from ToolBuilder. This is expected. We'll fix call sites in subsequent chunks.

- [ ] **Step 6: Commit (even with known regressions — we're mid-refactor)**

```bash
git add Sources/Swarm/Tools/ToolParameterBuilder.swift Tests/SwarmTests/V3/ToolBuilderV3Tests.swift
git commit -m "feat: rewrite ToolBuilder to produce ToolCollection instead of [any AnyJSONTool]"
```

---

## Chunk 3: Agent Canonical Init + Modifiers

Rewrite Agent to use single canonical init with progressive disclosure modifiers.

### Task 3.1: Add V3 canonical init and modifiers to Agent

**Files:**
- Modify: `Sources/Swarm/Agents/Agent.swift`
- Test: `Tests/SwarmTests/V3/AgentModifiersTests.swift`

- [ ] **Step 1: Write failing tests for Agent modifiers**

```swift
// Tests/SwarmTests/V3/AgentModifiersTests.swift
import Testing
@testable import Swarm

@Suite("Agent V3 Modifiers")
struct AgentModifiersTests {
    @Test("canonical init with instructions only")
    func minimalInit() throws {
        let agent = Agent("You are helpful")
        #expect(agent.instructions == "You are helpful")
        #expect(agent.tools.isEmpty)
    }

    @Test("canonical init with provider and tools")
    func initWithProviderAndTools() throws {
        let agent = Agent("Be helpful", provider: .mock()) {
            DateTimeTool()
        }
        #expect(agent.instructions == "Be helpful")
        #expect(agent.tools.count == 1)
    }

    @Test("memory modifier returns new agent with memory set")
    func memoryModifier() throws {
        let agent = Agent("test")
            .memory(.conversation(maxMessages: 50))
        #expect(agent.memory != nil)
    }

    @Test("tracer modifier returns new agent with tracer set")
    func tracerModifier() throws {
        let agent = Agent("test")
            .tracer(.console())
        #expect(agent.tracer != nil)
    }

    @Test("guardrails modifier sets input and output guardrails")
    func guardrailsModifier() throws {
        let agent = Agent("test")
            .guardrails(input: [.notEmpty()], output: [.maxLength(500)])
        #expect(agent.inputGuardrails.count == 1)
        #expect(agent.outputGuardrails.count == 1)
    }

    @Test("handoffs modifier sets handoff agents")
    func handoffsModifier() throws {
        let other = Agent("helper")
        let agent = Agent("triage")
            .handoffs([other])
        #expect(!agent.handoffs.isEmpty)
    }

    @Test("tools modifier with array of any Tool")
    func toolsArrayModifier() throws {
        let tools: [any Tool] = [DateTimeTool()]
        let agent = Agent("test")
            .tools(tools)
        #expect(agent.tools.count == 1)
    }

    @Test("callAsFunction executes agent")
    func callAsFunction() async throws {
        let agent = Agent("Say hello", provider: .mock(response: "Hello!"))
        let result = try await agent("Hi")
        #expect(result.output.contains("Hello"))
    }

    @Test("modifier chaining preserves all configuration")
    func chainingPreservesConfig() throws {
        let agent = Agent("test", provider: .mock()) {
            DateTimeTool()
        }
        .memory(.conversation())
        .tracer(.console())
        .guardrails(input: [.notEmpty()])

        #expect(agent.instructions == "test")
        #expect(agent.tools.count == 1)
        #expect(agent.memory != nil)
        #expect(agent.tracer != nil)
        #expect(agent.inputGuardrails.count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "AgentModifiersTests" 2>&1 | tail -10
```
Expected: FAIL — new init signature and modifiers don't exist yet.

- [ ] **Step 3: Add V3 canonical init to Agent.swift**

At the bottom of the initializer section in `Sources/Swarm/Agents/Agent.swift`, add:

```swift
// MARK: - V3 Final API

/// V3 canonical initializer — instructions-first with optional provider and @ToolBuilder trailing closure.
///
/// This is THE recommended path for creating agents:
/// ```swift
/// let agent = Agent("You are helpful", provider: .anthropic(apiKey: key)) {
///     WeatherTool()
///     SearchTool()
/// }
/// .memory(.conversation())
/// .tracer(.console())
/// ```
public init(
    _ instructions: String,
    provider: some InferenceProvider,
    @ToolBuilder tools: () -> ToolCollection = { .empty }
) {
    let toolStorage = tools().storage
    self.tools = toolStorage
    self.instructions = instructions
    self.configuration = .default
    self.memory = nil
    self.inferenceProvider = provider
    self.tracer = nil
    self.inputGuardrails = []
    self.outputGuardrails = []
    self.guardrailRunnerConfiguration = .default
    self._handoffs = []
    self.toolRegistry = (try? ToolRegistry(tools: toolStorage)) ?? ToolRegistry()
    self._publicTools = []  // populated below
}

/// V3 canonical initializer — instructions only (uses default provider resolution).
public init(
    _ instructions: String,
    @ToolBuilder tools: () -> ToolCollection = { .empty }
) {
    let toolStorage = tools().storage
    self.tools = toolStorage
    self.instructions = instructions
    self.configuration = .default
    self.memory = nil
    self.inferenceProvider = nil
    self.tracer = nil
    self.inputGuardrails = []
    self.outputGuardrails = []
    self.guardrailRunnerConfiguration = .default
    self._handoffs = []
    self.toolRegistry = (try? ToolRegistry(tools: toolStorage)) ?? ToolRegistry()
    self._publicTools = []
}
```

- [ ] **Step 4: Add modifier methods to Agent.swift**

```swift
// MARK: - V3 Modifiers

extension Agent {
    /// Sets the memory system for this agent.
    public func memory(_ memory: some Memory) -> Agent {
        var copy = self
        copy.memory = memory
        return copy
    }

    /// Sets the tracer for observability.
    public func tracer(_ tracer: any Tracer) -> Agent {
        var copy = self
        copy.tracer = tracer
        return copy
    }

    /// Sets input and/or output guardrails.
    public func guardrails(
        input: [any InputGuardrail] = [],
        output: [any OutputGuardrail] = []
    ) -> Agent {
        var copy = self
        copy.inputGuardrails = input
        copy.outputGuardrails = output
        return copy
    }

    /// Sets handoff agents for multi-agent orchestration.
    public func handoffs(_ agents: [any AgentRuntime]) -> Agent {
        var copy = self
        copy._handoffs = agents.map { agent in
            AnyHandoffConfiguration(
                targetAgent: agent,
                toolNameOverride: nil,
                toolDescription: nil
            )
        }
        return copy
    }

    /// Sets tools from an array of `any Tool` (for dynamic/programmatic tool assignment).
    public func tools(_ tools: [any Tool]) -> Agent {
        var copy = self
        let bridged = tools.map { bridgeToolToAnyJSON($0) }
        copy.tools = bridged
        copy.toolRegistry = (try? ToolRegistry(tools: bridged)) ?? ToolRegistry()
        return copy
    }

    /// Sets tools from a `@ToolBuilder` closure.
    public func tools(@ToolBuilder _ tools: () -> ToolCollection) -> Agent {
        var copy = self
        let storage = tools().storage
        copy.tools = storage
        copy.toolRegistry = (try? ToolRegistry(tools: storage)) ?? ToolRegistry()
        return copy
    }

    /// Sets the agent configuration.
    public func configuration(_ config: AgentConfiguration) -> Agent {
        var copy = self
        copy.configuration = config
        return copy
    }

    /// Executes the agent with the given input using `callAsFunction` syntax.
    ///
    /// ```swift
    /// let result = try await agent("Hello")
    /// ```
    public func callAsFunction(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResult {
        try await run(input, session: session, observer: observer)
    }
}
```

- [ ] **Step 5: Make stored properties `var` where needed**

In Agent.swift, change the relevant `let` properties to `var` so modifiers can create modified copies:

```swift
// Change from `let` to `var` for properties that modifiers mutate:
public var tools: [any AnyJSONTool]
public var instructions: String
public var configuration: AgentConfiguration
public var memory: (any Memory)?
public var inferenceProvider: (any InferenceProvider)?
public var inputGuardrails: [any InputGuardrail]
public var outputGuardrails: [any OutputGuardrail]
public var tracer: (any Tracer)?
public var guardrailRunnerConfiguration: GuardrailRunnerConfiguration
```

Also ensure `toolRegistry` is `var`:
```swift
internal var toolRegistry: ToolRegistry
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter "AgentModifiersTests" 2>&1 | tail -10
```
Expected: Most tests PASS. Some may fail if `.mock()` provider factory or guardrail factories don't exist yet. Adjust test setup as needed.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swarm/Agents/Agent.swift Tests/SwarmTests/V3/AgentModifiersTests.swift
git commit -m "feat: add V3 canonical Agent init with modifier chain and callAsFunction"
```

---

## Chunk 4: AnyJSONTool Internal Seal

Make `AnyJSONTool` internal. This is the largest change — touches 20 files.

### Task 4.1: Make AnyJSONTool protocol internal

**Files:**
- Modify: `Sources/Swarm/Tools/Tool.swift` (line 32: `public protocol AnyJSONTool` → `internal protocol AnyJSONTool`)

- [ ] **Step 1: Change AnyJSONTool to internal**

In `Sources/Swarm/Tools/Tool.swift`, change:
```swift
public protocol AnyJSONTool: Sendable {
```
to:
```swift
internal protocol AnyJSONTool: Sendable {
```

Also change all `public extension AnyJSONTool` to `internal extension AnyJSONTool`.

- [ ] **Step 2: Build to identify all breakages**

```bash
swift build 2>&1 | grep "error:" | head -50
```

This will produce many errors. Record them — each is a file that needs updating.

- [ ] **Step 3: Commit the protocol change (build broken — intentional)**

```bash
git add Sources/Swarm/Tools/Tool.swift
git commit -m "refactor: make AnyJSONTool protocol internal (build intentionally broken)"
```

### Task 4.2: Make AnyJSONToolAdapter internal

**Files:**
- Modify: `Sources/Swarm/Tools/ToolBridging.swift`

- [ ] **Step 1: Change AnyJSONToolAdapter and asAnyJSONTool() to internal**

In `Sources/Swarm/Tools/ToolBridging.swift`:
- Change `public struct AnyJSONToolAdapter` → `internal struct AnyJSONToolAdapter`
- Change `public extension Tool` containing `asAnyJSONTool()` → `internal extension Tool`
- Change `public init` on AnyJSONToolAdapter → `internal init`
- Change `public let tool` → `internal let tool`
- Change `public var name/description/parameters` → keep as-is (protocol requirement)
- Change `public func execute` → keep as-is (protocol requirement)

- [ ] **Step 2: Commit**

```bash
git add Sources/Swarm/Tools/ToolBridging.swift
git commit -m "refactor: make AnyJSONToolAdapter internal"
```

### Task 4.3: Update AgentRuntime protocol

**Files:**
- Modify: `Sources/Swarm/Core/AgentRuntime.swift` (line 39)

- [ ] **Step 1: Keep `tools` as `[any AnyJSONTool]` in protocol (internal)**

Since `AgentRuntime` is a `public` protocol but `AnyJSONTool` is now `internal`, we need to change the tools requirement. However, this is a complex change because the entire runtime depends on this.

**Pragmatic approach:** Add a parallel public `toolSchemas` property and keep internal `tools`:

```swift
// In AgentRuntime protocol — keep tools internal
// Add new public computed property for external access
nonisolated var toolSchemas: [ToolSchema] { get }
```

Or simpler: make `AgentRuntime` keep `tools` but mark the protocol method `@_spi(Internal)`:

```swift
@_spi(Internal)
nonisolated var tools: [any AnyJSONTool] { get }
```

**Decision point:** The pragmatic approach is `@_spi(Internal)` on the tools property. This hides it from normal autocomplete while keeping it available for internal framework use and tests via `@testable import`.

- [ ] **Step 2: Apply `@_spi(Internal)` to AgentRuntime.tools**

- [ ] **Step 3: Commit**

```bash
git add Sources/Swarm/Core/AgentRuntime.swift
git commit -m "refactor: hide AgentRuntime.tools behind @_spi(Internal)"
```

### Task 4.4: Fix ToolRegistry public API

**Files:**
- Modify: `Sources/Swarm/Tools/Tool.swift` (ToolRegistry section, lines 531-723)

- [ ] **Step 1: Add public methods accepting `any Tool` and `some Tool`**

Keep existing internal methods. Add public wrappers:

```swift
// New public API
public init(tools: [any Tool]) throws {
    try self.init(tools: tools.map { bridgeToolToAnyJSON($0) } as [any AnyJSONTool])
}

public func register(_ tool: any Tool) throws {
    try register(bridgeToolToAnyJSON(tool) as any AnyJSONTool)
}
```

Make existing `init(tools: [any AnyJSONTool])` internal.

- [ ] **Step 2: Commit**

```bash
git add Sources/Swarm/Tools/Tool.swift
git commit -m "refactor: update ToolRegistry public API to use Tool protocol"
```

### Task 4.5: Fix remaining compilation errors

**Files:** Multiple — all files that reference `AnyJSONTool` in public context.

- [ ] **Step 1: Build and fix each error one file at a time**

```bash
swift build 2>&1 | grep "error:" | head -20
```

For each file:
- If it's a public API that exposes `AnyJSONTool` → change to use `Tool` or `ToolCollection` or `@_spi(Internal)`
- If it's internal implementation → ensure it can still access the internal `AnyJSONTool`
- Framework-internal files (MCP, HiveSwarm, etc.) that use `any AnyJSONTool` internally → no change needed, they're in the same module

Files likely needing fixes:
- `AgentTool.swift` — conformance stays (internal protocol, same module)
- `BuiltInTools.swift` — conformance stays
- `FunctionTool.swift` — conformance stays
- `MCPToolBridge.swift` — internal bridging stays
- `HiveSwarm/ToolRegistryAdapter.swift` — internal stays
- `HiveSwarm/GraphAgent.swift` — internal stays
- `ToolGuardrails.swift` — internal stays
- `MacroDeclarations.swift` — update docs only

- [ ] **Step 2: Fix each file, building after each**

```bash
swift build 2>&1 | grep "error:" | wc -l
```

Repeat until 0 errors.

- [ ] **Step 3: Run full test suite**

```bash
swift test 2>&1 | tail -20
```

Fix any test failures caused by the internal seal.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: fix all compilation errors from AnyJSONTool internal seal"
```

---

## Chunk 5: Memory Protocol Migration

### Task 5.1: Remove Actor requirement from Memory protocol

**Files:**
- Modify: `Sources/Swarm/Memory/AgentMemory.swift` (line 47)

- [ ] **Step 1: Remove `: Actor` from Memory protocol**

Change:
```swift
public protocol Memory: Actor, Sendable {
```
to:
```swift
public protocol Memory: Sendable {
```

Update the doc comments to reflect that implementations are no longer required to be actors (but CAN still be actors).

- [ ] **Step 2: Build and check for errors**

```bash
swift build 2>&1 | grep "error:" | head -20
```

Existing actor implementations (`ConversationMemory`, `VectorMemory`, etc.) will still compile because actors are `Sendable`. The change is backward-compatible for conforming types.

- [ ] **Step 3: Commit**

```bash
git add Sources/Swarm/Memory/AgentMemory.swift
git commit -m "refactor: remove Actor requirement from Memory protocol"
```

### Task 5.2: Add factory extensions to Memory protocol

**Files:**
- Modify: `Sources/Swarm/Memory/AgentMemory.swift`

- [ ] **Step 1: Add constrained static factory extensions**

Below the `AnyMemory` definition (which we'll delete later), add:

```swift
// MARK: - Memory Factory Extensions

extension Memory where Self == ConversationMemory {
    /// Creates a conversation memory with a maximum message count.
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory {
        ConversationMemory(maxMessages: maxMessages)
    }
}

extension Memory where Self == SlidingWindowMemory {
    /// Creates a sliding window memory with a maximum token count.
    public static func slidingWindow(maxTokens: Int = 4000) -> SlidingWindowMemory {
        SlidingWindowMemory(maxTokens: maxTokens)
    }
}

extension Memory where Self == VectorMemory {
    /// Creates a vector memory with semantic search.
    public static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> VectorMemory {
        VectorMemory(
            embeddingProvider: embeddingProvider,
            similarityThreshold: similarityThreshold,
            maxResults: maxResults
        )
    }
}

extension Memory where Self == PersistentMemory {
    /// Creates a persistent memory with a storage backend.
    public static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> PersistentMemory {
        PersistentMemory(
            backend: backend,
            conversationId: conversationId,
            maxMessages: maxMessages
        )
    }
}
```

- [ ] **Step 2: Write test for factory methods**

```swift
// Tests/SwarmTests/V3/MemoryFactoryV3Tests.swift
import Testing
@testable import Swarm

@Suite("Memory V3 Factories")
struct MemoryFactoryV3Tests {
    @Test("conversation factory creates ConversationMemory")
    func conversationFactory() async {
        let memory: some Memory = .conversation(maxMessages: 50)
        #expect(await memory.count == 0)
    }

    @Test("slidingWindow factory creates SlidingWindowMemory")
    func slidingWindowFactory() async {
        let memory: some Memory = .slidingWindow(maxTokens: 2000)
        #expect(await memory.count == 0)
    }

    @Test("persistent factory creates PersistentMemory")
    func persistentFactory() async {
        let memory: some Memory = .persistent()
        #expect(await memory.count == 0)
    }

    @Test("dot-syntax works with Agent modifier")
    func dotSyntaxWithAgent() throws {
        let agent = Agent("test")
            .memory(.conversation())
        #expect(agent.memory != nil)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter "MemoryFactoryV3Tests" 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Swarm/Memory/AgentMemory.swift Tests/SwarmTests/V3/MemoryFactoryV3Tests.swift
git commit -m "feat: add Memory factory extensions for dot-syntax (.conversation(), .vector(), etc.)"
```

---

## Chunk 6: Guardrail Factories

### Task 6.1: Add static factories to InputGuard and OutputGuard

**Files:**
- Modify: `Sources/Swarm/Guardrails/InputGuardrail.swift`
- Modify: `Sources/Swarm/Guardrails/OutputGuardrail.swift`
- Test: `Tests/SwarmTests/V3/GuardrailFactoryV3Tests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SwarmTests/V3/GuardrailFactoryV3Tests.swift
import Testing
@testable import Swarm

@Suite("Guardrail V3 Factories")
struct GuardrailFactoryV3Tests {
    @Test("notEmpty factory creates InputGuard")
    func notEmpty() async throws {
        let guardrail: any InputGuardrail = .notEmpty()
        let result = try await guardrail.validate(input: "hello", context: .init())
        #expect(!result.tripwireTriggered)
    }

    @Test("maxLength factory creates InputGuard")
    func maxLength() async throws {
        let guardrail: any InputGuardrail = .maxLength(5)
        let result = try await guardrail.validate(input: "toolong", context: .init())
        #expect(result.tripwireTriggered)
    }

    @Test("custom factory creates InputGuard")
    func custom() async throws {
        let guardrail: any InputGuardrail = .custom("no-bad-words") { input, _ in
            GuardrailResult(tripwireTriggered: input.contains("bad"))
        }
        let result = try await guardrail.validate(input: "bad word", context: .init())
        #expect(result.tripwireTriggered)
    }
}
```

- [ ] **Step 2: Implement factories**

Check if `InputGuard` struct already exists. If yes, add factories. If not, create it.
Add constrained protocol extensions:

```swift
extension InputGuardrail where Self == InputGuard {
    public static func notEmpty() -> InputGuard { ... }
    public static func maxLength(_ n: Int) -> InputGuard { ... }
    public static func custom(_ name: String, _ check: @Sendable (String, GuardrailContext) async throws -> GuardrailResult) -> InputGuard { ... }
}
```

Same pattern for `OutputGuardrail where Self == OutputGuard`.

- [ ] **Step 3: Run tests, verify pass**

- [ ] **Step 4: Commit**

```bash
git add Sources/Swarm/Guardrails/ Tests/SwarmTests/V3/GuardrailFactoryV3Tests.swift
git commit -m "feat: add InputGuard/OutputGuard static factories (.notEmpty(), .maxLength(), .custom())"
```

---

## Chunk 7: Tracer and RetryPolicy Factories

### Task 7.1: Add Tracer factory extensions

**Files:**
- Modify: `Sources/Swarm/Observability/AgentTracer.swift` or relevant tracer file
- Test: existing V3 tests or new

- [ ] **Step 1: Check if factory extensions already exist**

```bash
grep -n "extension Tracer where Self ==" Sources/Swarm/Observability/*.swift
```

If they exist, verify. If not, add:

```swift
extension Tracer where Self == ConsoleTracer {
    public static func console(verbose: Bool = false) -> ConsoleTracer { ... }
}
```

- [ ] **Step 2: Check RetryPolicy factories**

```bash
grep -n "extension RetryPolicy where Self ==" Sources/Swarm/Resilience/*.swift
```

If missing, add. If present, verify.

- [ ] **Step 3: Commit**

```bash
git add Sources/Swarm/Observability/ Sources/Swarm/Resilience/
git commit -m "feat: add Tracer and RetryPolicy factory extensions for dot-syntax"
```

---

## Chunk 8: #Tool Freestanding Expression Macro

### Task 8.1: Implement InlineToolMacro

**Files:**
- Create: `Sources/SwarmMacros/InlineToolMacro.swift`
- Modify: `Sources/SwarmMacros/Plugin.swift`
- Modify: `Sources/Swarm/Macros/MacroDeclarations.swift`
- Test: `Tests/SwarmMacrosTests/InlineToolMacroTests.swift`

- [ ] **Step 1: Add macro declaration**

In `Sources/Swarm/Macros/MacroDeclarations.swift`, add:

```swift
/// Creates an inline tool from a closure with labeled parameters.
///
/// ```swift
/// #Tool("greet", "Says hello") { (name: String) in
///     "Hello, \(name)!"
/// }
/// ```
@freestanding(expression)
public macro Tool(
    _ name: String,
    _ description: String,
    body: () -> Void = {}
) -> any Tool = #externalMacro(module: "SwarmMacros", type: "InlineToolMacro")
```

- [ ] **Step 2: Implement InlineToolMacro.swift**

Create `Sources/SwarmMacros/InlineToolMacro.swift`:

```swift
import SwiftSyntax
import SwiftSyntaxMacros

public struct InlineToolMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // 1. Extract name and description from first two arguments
        // 2. Extract trailing closure and its parameter list
        // 3. For each (label: Type) param, generate:
        //    - A field in the Codable Input struct
        //    - A ToolParameter entry
        // 4. Generate Tool-conforming struct with typed execute method
        // 5. Wrap in IIFE: { struct ...; return Instance() }()

        // Implementation uses SwiftSyntax to parse ClosureExprSyntax
        // See spec Section 3 for full expansion template
        fatalError("TODO: implement InlineToolMacro")
    }
}
```

The full implementation requires ~100-150 lines of SwiftSyntax code. Key steps:
- Parse `node.arguments` for name/description string literals
- Parse `node.trailingClosure` for `ClosureExprSyntax`
- Extract `closure.signature.parameterClause` for parameter labels/types
- Map Swift types to `ToolParameter.ParameterType` (String→.string, Int→.int, etc.)
- Generate the anonymous struct code as a `CodeBlockItemListSyntax`

- [ ] **Step 3: Register in Plugin.swift**

```swift
let providingMacros: [Macro.Type] = [
    ToolMacro.self,
    ParameterMacro.self,
    AgentMacro.self,
    TraceableMacro.self,
    PromptMacro.self,
    BuilderMacro.self,
    InlineToolMacro.self   // NEW
]
```

- [ ] **Step 4: Write tests**

```swift
// Tests/SwarmMacrosTests/InlineToolMacroTests.swift
import Testing
import SwiftSyntaxMacrosTestSupport
@testable import SwarmMacros

@Suite("InlineToolMacro")
struct InlineToolMacroTests {
    @Test("expands simple single-parameter tool")
    func singleParam() {
        assertMacroExpansion(
            """
            #Tool("greet", "Says hello") { (name: String) in
                "Hello, \\(name)!"
            }
            """,
            expandedSource: """
            {
                struct _InlineTool_greet: Tool, Sendable {
                    // ... expanded code
                }
                return _InlineTool_greet()
            }()
            """,
            macros: ["Tool": InlineToolMacro.self]
        )
    }

    @Test("expands multi-parameter tool")
    func multiParam() {
        // Test with (name: String, age: Int) parameters
    }

    @Test("expands optional parameter")
    func optionalParam() {
        // Test with (name: String, title: String?) parameters
    }
}
```

- [ ] **Step 5: Implement the full macro, iterate until tests pass**

- [ ] **Step 6: Commit**

```bash
git add Sources/SwarmMacros/InlineToolMacro.swift Sources/SwarmMacros/Plugin.swift Sources/Swarm/Macros/MacroDeclarations.swift Tests/SwarmMacrosTests/InlineToolMacroTests.swift
git commit -m "feat: add #Tool freestanding expression macro for inline tool creation"
```

---

## Chunk 9: @Tool Macro Conformance Change

### Task 9.1: Update @Tool macro to generate Tool conformance

**Files:**
- Modify: `Sources/SwarmMacros/ToolMacro.swift` (line 142)
- Modify: `Sources/Swarm/Macros/MacroDeclarations.swift` (update attached conformances)

- [ ] **Step 1: Change conformance generation**

In `ToolMacro.swift`, change line 142:
```swift
let toolExtension = try ExtensionDeclSyntax("extension \(type): AnyJSONTool, Sendable {}")
```
to:
```swift
let toolExtension = try ExtensionDeclSyntax("extension \(type): Tool, Sendable {}")
```

In `MacroDeclarations.swift`, update the `@Tool` macro declaration's conformances:
```swift
@attached(extension, conformances: Tool, Sendable)
```

- [ ] **Step 2: Update the execute wrapper generation**

The macro currently generates `func execute(arguments: [String: SendableValue])`. This needs to change to generate `func execute(_ input: SomeInput)` where `SomeInput` is a generated Codable struct.

This is a significant change to `ToolMacro.swift`'s `generateExecuteWrapper` method. The new generation should:
1. Create a `typealias Input = <ToolName>Input`
2. Create a `struct <ToolName>Input: Codable, Sendable` with the `@Parameter` properties
3. Generate `func execute(_ input: <ToolName>Input) async throws -> <OutputType>`

- [ ] **Step 3: Update macro tests**

- [ ] **Step 4: Run full test suite**

```bash
swift test 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add Sources/SwarmMacros/ToolMacro.swift Sources/Swarm/Macros/MacroDeclarations.swift Tests/SwarmMacrosTests/
git commit -m "refactor: @Tool macro generates Tool conformance instead of AnyJSONTool"
```

---

## Chunk 10: Cleanup — Delete Deprecated Types

### Task 10.1: Delete type-eraser wrappers

**Files to delete/modify:**
- Delete: `Sources/Swarm/Memory/MemoryBuilder.swift` (532 lines)
- Modify: `Sources/Swarm/Memory/AgentMemory.swift` — delete `AnyMemory` actor (lines 155-220)

- [ ] **Step 1: Delete MemoryBuilder.swift**

```bash
git rm Sources/Swarm/Memory/MemoryBuilder.swift
```

- [ ] **Step 2: Delete AnyMemory from AgentMemory.swift**

Remove the `AnyMemory` actor and its factory extensions (lines ~155-281). The factory extensions have been moved to constrained protocol extensions in Chunk 5.

- [ ] **Step 3: Build and fix any references to deleted types**

```bash
swift build 2>&1 | grep "error:" | head -20
```

Update any code referencing `AnyMemory` or `MemoryBuilder` to use `any Memory` + factory methods.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete AnyMemory and MemoryBuilder (replaced by protocol factories)"
```

### Task 10.2: Delete ClosureInputGuardrail and ClosureOutputGuardrail

- [ ] **Step 1: Find and remove these types**

```bash
grep -rn "ClosureInputGuardrail\|ClosureOutputGuardrail" Sources/
```

Delete the types. Update any references to use `InputGuard.custom()` / `OutputGuard.custom()`.

- [ ] **Step 2: Build and fix**

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor: delete ClosureInputGuardrail/ClosureOutputGuardrail (use .custom() factory)"
```

### Task 10.3: Delete deprecated types

- [ ] **Step 1: Find and delete ParallelComposition, AgentSequence**

```bash
grep -rn "ParallelComposition\|AgentSequence" Sources/
```

- [ ] **Step 2: Remove deprecated ChatGraph methods and Workflow+Durable overload**

- [ ] **Step 3: Build, fix references, test**

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete deprecated types (ParallelComposition, AgentSequence, old ChatGraph methods)"
```

---

## Chunk 11: Integration Fixes + Full Test Pass

### Task 11.1: Fix any remaining build errors

- [ ] **Step 1: Full build**

```bash
swift build 2>&1 | grep "error:" | wc -l
```

- [ ] **Step 2: Fix each error**

- [ ] **Step 3: Full test suite**

```bash
swift test 2>&1 | tail -30
```

- [ ] **Step 4: Compare test counts with baseline from Pre-flight**

Ensure no test regressions beyond intentionally removed tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix: resolve all remaining build errors and test failures from V3 refactor"
```

### Task 11.2: Update existing V3 tests

**Files:**
- Modify: `Tests/SwarmTests/V3/AgentCanonicalInitTests.swift`
- Modify: `Tests/SwarmTests/V3/ZombieAPIRemovalTests.swift`

- [ ] **Step 1: Update AgentCanonicalInitTests to test new init**

- [ ] **Step 2: Update ZombieAPIRemovalTests to verify deleted types are gone**

- [ ] **Step 3: Run V3 tests**

```bash
swift test --filter "V3" 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
git add Tests/SwarmTests/V3/
git commit -m "test: update V3 tests for final push API changes"
```

---

## Chunk 12: AI Agent Eval

### Task 12.1: Run agent eval prompts

- [ ] **Step 1: Create eval test file**

```swift
// Tests/SwarmTests/V3/AgentEvalTests.swift
import Testing
@testable import Swarm

@Suite("V3 Agent Eval — Can an AI create these?")
struct AgentEvalTests {
    @Test("minimal agent creation")
    func eval01_minimal() throws {
        let agent = Agent("You are helpful")
        #expect(agent.instructions == "You are helpful")
    }

    @Test("agent with provider and tools")
    func eval02_withTools() throws {
        let agent = Agent("Be helpful", provider: .mock()) {
            DateTimeTool()
        }
        #expect(agent.tools.count == 1)
    }

    @Test("agent with full modifier chain")
    func eval03_fullChain() throws {
        let agent = Agent("Be helpful", provider: .mock()) {
            DateTimeTool()
        }
        .memory(.conversation())
        .guardrails(input: [.notEmpty()])

        #expect(agent.memory != nil)
        #expect(agent.inputGuardrails.count == 1)
    }

    @Test("callAsFunction works")
    func eval04_callAsFunction() async throws {
        let agent = Agent("Say OK", provider: .mock(response: "OK"))
        let result = try await agent("Hi")
        #expect(result.output.contains("OK"))
    }

    @Test("AnyJSONTool is not visible in public API")
    func eval05_noAnyJSONTool() {
        // This test verifies AnyJSONTool doesn't appear in autocomplete
        // by checking that Agent.tools returns [any Tool]-compatible types
        let agent = Agent("test")
        let _ = agent.instructions // public
        // agent.tools should not expose AnyJSONTool — verified by compilation
    }
}
```

- [ ] **Step 2: Run eval tests**

```bash
swift test --filter "AgentEvalTests" 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add Tests/SwarmTests/V3/AgentEvalTests.swift
git commit -m "test: add V3 AI agent eval tests"
```

---

## Post-flight

- [ ] **Step 1: Final full build + test**

```bash
swift build && swift test 2>&1 | tail -20
```

- [ ] **Step 2: Count public types**

```bash
grep -rn "^public \(struct\|class\|actor\|enum\|protocol\)" Sources/Swarm/ | wc -l
```

Target: ~70 (down from 197).

- [ ] **Step 3: Verify no public AnyJSONTool references**

```bash
grep -rn "public.*AnyJSONTool" Sources/Swarm/ | grep -v "@_spi"
```

Expected: 0 results.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: V3 API final push complete — AnyJSONTool sealed, modifier pattern, ~70 public types"
```
