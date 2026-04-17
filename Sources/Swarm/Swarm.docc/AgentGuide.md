# Using Agent

Creating, configuring, and running an ``Agent``.

## Overview

An ``Agent`` wraps an inference provider in a runtime loop that handles tool
calls, memory, guardrails, session history, and handoffs. You configure it
once, then call ``Agent/run(_:session:observer:)`` (or one of its variants)
as many times as you want.

## Picking an initializer

``Agent`` ships five primary initializers plus two convenience overloads.
Pick based on *what information you have at the call site*:

| You have… | Use |
|---|---|
| An `@Tool` struct or two | `Agent(_:configuration:... tools:)` — instructions-first with `@ToolBuilder` |
| A specific ``InferenceProvider`` value, always | `Agent(_ instructions: String, provider:...)` — explicit-provider variant |
| An existing `InferenceProvider` and don't want to repeat the label | `Agent(_:)` — unlabeled-provider convenience |
| Already-type-erased `[any AnyJSONTool]` | `Agent(tools:instructions:...)` — canonical init |
| A strongly-typed `[some Tool]` array | `Agent(tools:instructions:...)` — typed-tool init |
| A display name you want merged into the configuration | `Agent(name:instructions:...)` — name-first convenience |
| Bare agents as handoff targets | `Agent(name:instructions:...,handoffAgents:)` or `Agent(tools:...,handoffAgents:)` |

### Recommended init for most new code

```swift
let agent = try Agent("You are a helpful assistant.") {
    WeatherTool()
    CalculatorTool()
}

// With an explicit provider:
let agent = try Agent(
    "You are a helpful assistant.",
    provider: .anthropic(key: apiKey)
) {
    WeatherTool()
}
```

The trailing `@ToolBuilder` closure composes tools the same way SwiftUI
composes views — `if`/`for`/variadic expressions all work inside.

## Provider resolution order

When an agent needs to make an LLM call, it walks the following list and
uses the first provider it finds:

1. An explicit provider passed to the agent's initializer.
2. A provider attached via the environment:
   `.environment(\.inferenceProvider, provider)`.
3. `Swarm.defaultProvider` — set once in your app startup via
   `await Swarm.configure(provider: ...)`.
4. `Swarm.cloudProvider` — set via `await Swarm.configure(cloudProvider: ...)`.
   Used when tool calling is required and no other provider can satisfy it.
5. Apple Foundation Models — on supported Apple platforms, with prompt-based
   tool emulation when native tool calling isn't available.
6. Otherwise, the agent throws
   ``AgentError/inferenceProviderUnavailable(reason:)``.

Set `Swarm.configure(provider:)` at app launch and you rarely need to think
about it again; per-agent overrides compose on top.

## Three ways to construct

- **Direct init** (above) — simplest, what you want for most code.
- **``Agent/Builder``** — fluent, chainable, useful when construction
  happens across multiple scopes or depends on optional wiring you don't
  want to build via `var`s:

  ```swift
  let agent = try Agent.Builder()
      .instructions("You are a helpful assistant.")
      .inferenceProvider(.anthropic(key: apiKey))
      .tools([WeatherTool(), CalculatorTool()])
      .inputGuardrails([.notEmpty(), .maxLength(4_000)])
      .build()
  ```

- **V3 modifiers** (``Agent/withMemory(_:)``, ``Agent/withTracer(_:)``,
  ``Agent/withGuardrails(input:output:)``, ``Agent/withHandoffs(_:)``,
  ``Agent/withTools(_:)-8t9cq``, ``Agent/withConfiguration(_:)``) — work on
  an already-built agent:

  ```swift
  let agent = try Agent("Be helpful.")
      .withMemory(.conversation(maxMessages: 50))
      .withGuardrails(input: [.notEmpty(), .maxLength(4_000)])
  ```

  Modifiers return a new `Agent` value (the original is unchanged).

## Running an agent

Five entry points, each suited to a different consumer:

| Method | Returns | Use when |
|---|---|---|
| ``Agent/run(_:session:observer:)`` | ``AgentResult`` | You want the final answer and don't care about intermediate events |
| ``Agent/stream(_:session:observer:)`` | `AsyncThrowingStream<AgentEvent, Error>` | You're driving a UI and want incremental thinking / tool / text events |
| ``Agent/runStructured(_:request:session:observer:)`` | ``StructuredAgentResult`` | You need the response to match a specific `Codable` schema |
| ``Agent/runWithResponse(_:session:observer:)`` | ``AgentResponse`` | You want `AgentResult` plus a response ID for session continuation |
| ``Agent/callAsFunction(_:session:observer:)`` | ``AgentResult`` | You want `agent("hello")` syntactic sugar |

`run` is the workhorse; everything else is a specialization. See
<doc:Streaming> for what you get out of `stream`, and <doc:ErrorHandling>
for the error taxonomy.

## Sessions

Pass an optional ``Session`` to any of the run methods to persist the
conversation across turns:

```swift
let session = InMemorySession()
_ = try await agent.run("Hello, I'm Alice.", session: session)
_ = try await agent.run("What's my name?", session: session) // remembers
```

Memory (retrieved context) is a different concern — see
<doc:MemoryAndSessions>.

## Handoffs

Handoffs let the model transfer control to another agent by name. Declare
them on the agent:

```swift
// With the handoffs: parameter (existing AnyHandoffConfiguration):
let triage = try Agent(
    instructions: "Route requests to the right specialist.",
    handoffs: [
        AnyHandoffConfiguration(targetAgent: billingAgent),
        AnyHandoffConfiguration(targetAgent: supportAgent)
    ]
)

// Or with the handoffAgents: shortcut that auto-wraps:
let triage = try Agent(
    name: "Triage",
    instructions: "Route requests to the right specialist.",
    handoffAgents: [billingAgent, supportAgent]
)

// Or via the Builder:
let triage = try Agent.Builder()
    .instructions("Route requests to the right specialist.")
    .handoffs(billingAgent, supportAgent)   // variadic parameter pack
    .build()

// Or via modifiers:
let triage = try Agent("Route requests.")
    .withHandoffs([billingAgent, supportAgent])
```

For the orchestration mechanics (parallel handoffs, routing, workflow
composition), see <doc:WorkflowComposition>.

## Cross-references

- Tools and `@Tool` macro → <doc:ToolAuthoring>
- Memory and Session distinction → <doc:MemoryAndSessions>
- Guardrails → <doc:Guardrails>
- Workflow / orchestration → <doc:WorkflowComposition>
- Streaming / `AgentEvent` → <doc:Streaming>
- Errors → <doc:ErrorHandling>

## See also

- ``AgentRuntime``
- ``AgentConfiguration``
- ``AgentResult``
- ``AgentResponse``
- ``Agent/Builder``
