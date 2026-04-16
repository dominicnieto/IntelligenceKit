# Error Handling

Patterns for catching, recovering from, and surfacing errors raised by Swarm.

## Overview

Swarm operations throw ``AgentError`` for agent-level failures,
``GuardrailError`` for guardrail tripwires, and ``WorkflowError`` for workflow
composition failures. All three conform to `LocalizedError`, so
`errorDescription` and `recoverySuggestion` are safe to surface in UI.

Most errors fall into three categories:

- **Transient** — worth retrying (rate limits, provider blips, generation hiccups)
- **Configuration** — needs developer action (missing tool, wrong model name, no provider)
- **Terminal** — the operation should stop (cancellation, guardrail violation, context too large)

``AgentError/recoverySuggestion`` returns a short hint for cases where a
generic recovery message is meaningful. Where richer recovery is possible,
use the patterns below.

## Rate limits and transient failures

``AgentError/rateLimitExceeded(retryAfter:)`` carries the provider's recommended
delay when available. A small retry loop with exponential backoff handles both
rate limits and ``AgentError/generationFailed(reason:)``:

```swift
func runWithRetry(_ agent: Agent, input: String, attempts: Int = 3) async throws -> AgentResult {
    var delay: Duration = .seconds(1)
    for attempt in 1...attempts {
        do {
            return try await agent.run(input)
        } catch AgentError.rateLimitExceeded(let retryAfter) {
            if attempt == attempts { throw AgentError.rateLimitExceeded(retryAfter: retryAfter) }
            let wait = retryAfter.map { Duration.seconds($0) } ?? delay
            try await Task.sleep(for: wait)
            delay *= 2
        } catch AgentError.generationFailed {
            if attempt == attempts { throw AgentError.generationFailed(reason: "retries exhausted") }
            try await Task.sleep(for: delay)
            delay *= 2
        }
    }
    preconditionFailure("unreachable")
}
```

## Falling back to a different provider

``AgentError/inferenceProviderUnavailable(reason:)`` means the configured
provider couldn't be reached. Pass an explicit fallback provider to a second
agent and retry with it:

```swift
do {
    return try await primaryAgent.run(input)
} catch AgentError.inferenceProviderUnavailable {
    let fallback = try Agent(.anthropic(key: anthropicKey), instructions: primaryAgent.instructions)
    return try await fallback.run(input)
}
```

You can also configure a cloud provider globally so agents fall back to it
automatically when their primary path requires tool calling:

```swift
await Swarm.configure(cloudProvider: .anthropic(key: anthropicKey))
```

## Managing the context window

``AgentError/contextWindowExceeded(tokenCount:limit:)`` means the prompt plus
conversation history exceeded the model's window. Two practical fixes:

- **Trim the session**. Each `AgentConfiguration` has a `sessionHistoryLimit`
  (default 50). Lower it for long-running conversations.
- **Switch to a larger-window provider**. Create the agent with a different
  `InferenceProvider` that targets a model with more headroom.

```swift
let config = AgentConfiguration(sessionHistoryLimit: 20)
let agent = try Agent(
    tools: [],
    instructions: "...",
    configuration: config,
    inferenceProvider: .anthropic(key: anthropicKey)
)
```

## Tool errors

``AgentError/toolNotFound(name:)`` almost always means a typo or a forgotten
tool registration. The agent only knows about tools you passed to its
initializer:

```swift
let agent = try Agent(
    tools: [WeatherTool(), CalculatorTool()],
    instructions: "..."
)
// The model can only call "weather" and "calculator" — nothing else.
```

``AgentError/toolExecutionFailed(toolName:underlyingError:)`` wraps whatever
your tool's `execute` threw. Handle it like any other thrown error, and decide
per-tool whether to retry, return an empty result, or surface the failure.

``AgentError/invalidToolArguments(toolName:reason:)`` means the model
generated arguments that failed your tool's schema validation. Clearer
parameter descriptions in your `@Tool` usually fix this — the model needs
enough signal to produce well-typed arguments on the first try.

## Iteration and timeout limits

``AgentError/maxIterationsExceeded(iterations:)`` and ``AgentError/timeout(duration:)``
are soft limits. Increase them on the agent's configuration if the task
legitimately needs more room:

```swift
let config = AgentConfiguration(
    maxIterations: 25,
    timeout: .seconds(120)
)
```

If you're consistently hitting the limits, that's a sign the task needs
decomposition — either into a multi-step ``Workflow`` or smaller subtasks
that run sequentially.

## Cancellation

``AgentError/cancelled`` is non-retryable by design. It means the enclosing
`Task` was cancelled (or you invoked `agent.cancel()`). Treat it as a clean
exit, not an error worth surfacing:

```swift
do {
    return try await agent.run(input)
} catch AgentError.cancelled {
    return nil  // clean exit, no alert
}
```

## Guardrail and content-filter errors

``AgentError/guardrailViolation(reason:)`` comes from a guardrail **you**
configured on the agent. ``AgentError/contentFiltered(reason:)`` comes from
the provider's own safety system and is outside your control.

Both are usually terminal for the current request. The response to a
guardrail violation is to refine the prompt or adjust the guardrail; the
response to provider-side filtering is to rephrase the input.

## Surfacing errors to users

For UI, `errorDescription` plus `recoverySuggestion` is usually the right
pair:

```swift
} catch let error as AgentError {
    let message = error.errorDescription ?? "Unknown error"
    let hint = error.recoverySuggestion
    showAlert(title: message, detail: hint)
}
```

For logging and debugging, use the `debugDescription` property (via
`String(reflecting:)`) instead — it includes the associated values verbatim.
