# Guardrails

Validating what goes into an agent and what comes out.

## Overview

Two protocols, same shape:

- ``InputGuardrail`` runs **before** the agent processes a user's input.
- ``OutputGuardrail`` runs **after** the agent produces a response, before
  it's returned to the caller.

Each validator returns a ``GuardrailResult``: `.passed(...)` lets the turn
proceed, `.tripwire(...)` blocks it and causes the runner to raise a
``GuardrailError``. `Guardrail` is the common parent protocol both inherit.

## Pipeline

```
user input
    │
    ▼
[ input guardrails ]  ──tripwire──►  GuardrailError.inputTripwireTriggered
    │
    ▼
  agent runs tools / generates response
    │
    ▼
[ output guardrails ] ──tripwire──►  GuardrailError.outputTripwireTriggered
    │
    ▼
 AgentResult returned to caller
```

Multiple guardrails of either type run in sequence (or in parallel, depending
on the ``GuardrailRunnerConfiguration``). The first tripwire stops the pipeline.

## Picking an implementation

You have three paths, from least to most machinery:

1. **Static factories.** `InputGuard.maxLength(5000)`, `InputGuard.notEmpty()`,
   `OutputGuard.maxLength(2000)`. Best for built-in checks.
2. **Closure wrappers.** ``InputGuard`` / ``OutputGuard`` initializers take a
   closure and a name. Best for one-off custom checks that don't warrant a
   dedicated type.
3. **Protocol conformance.** Define your own struct conforming to
   ``InputGuardrail`` / ``OutputGuardrail``. Best for non-trivial guards that
   carry state, dependencies, or need testable interfaces.

## Attaching to agents

Pass arrays to the Agent initializer:

```swift
let agent = try Agent(
    tools: [],
    instructions: "You are a helpful assistant.",
    inputGuardrails: [
        .notEmpty(),
        .maxLength(5000),
        .custom("no_scripts") { input in
            input.contains("<script")
                ? .tripwire(message: "Scripts not allowed")
                : .passed()
        }
    ],
    outputGuardrails: [
        .maxLength(10_000),
        .custom("no_emails") { output in
            let pattern = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(output.startIndex..., in: output)
            return regex.firstMatch(in: output, options: [], range: range) == nil
                ? .passed()
                : .tripwire(message: "Email addresses not allowed in output")
        }
    ]
)
```

The `.notEmpty()` / `.maxLength(...)` / `.custom(...)` syntax works because the
factories are re-exported as protocol-extension static methods on
`InputGuardrail where Self == InputGuard` (and the same for output). This
gives you type inference inside `[any InputGuardrail]` literals.

## Closure-based guards

``InputGuard`` has two init overloads:

```swift
// Input-only closure
let noProfanity = InputGuard("no_profanity") { input in
    containsProfanity(input)
        ? .tripwire(message: "Inappropriate language")
        : .passed()
}

// Context-aware closure — use when the decision depends on shared state
let rateLimited = InputGuard("rate_limited") { input, context in
    let count = await context?.get("requestCount")?.intValue ?? 0
    guard count < 100 else {
        return .tripwire(message: "Rate limit exceeded")
    }
    await context?.set("requestCount", value: .int(count + 1))
    return .passed()
}
```

``OutputGuard`` has three, adding the producing ``AgentRuntime``:

```swift
// Output-only
let noProfanityOut = OutputGuard("no_profanity") { output in
    containsProfanity(output) ? .tripwire(message: "blocked") : .passed()
}

// Output + context
let strictGuard = OutputGuard("strict_mode") { output, context in
    let strict = await context?.get("strict")?.boolValue ?? false
    return strict && containsForbidden(output)
        ? .tripwire(message: "blocked")
        : .passed()
}

// Output + agent + context — use when rules vary per agent
let agentScoped = OutputGuard("agent_scoped") { output, agent, context in
    let name = agent.configuration.name
    let limit = name == "concise" ? 100 : 10_000
    return output.count <= limit
        ? .passed()
        : .tripwire(message: "Too long for \(name)")
}
```

## Protocol conformance

When a guardrail grows beyond a closure — e.g. it carries configuration,
dependencies, or needs test doubles — conform to the protocol directly:

```swift
struct PIIRedactionGuardrail: OutputGuardrail {
    let name = "PIIRedaction"
    let patterns: [NSRegularExpression]

    func validate(
        _ output: String,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> GuardrailResult {
        let range = NSRange(output.startIndex..., in: output)
        for regex in patterns {
            if regex.firstMatch(in: output, options: [], range: range) != nil {
                return .tripwire(
                    message: "PII detected in output",
                    outputInfo: .dictionary(["type": .string("EMAIL")]),
                    metadata: ["redacted": .bool(true)]
                )
            }
        }
        return .passed()
    }
}
```

The same shape applies to ``InputGuardrail``; the `validate` method just
takes `(input, context)` rather than `(output, agent, context)`.

## Composing

Return `[any InputGuardrail]` (or the output counterpart) from a helper —
this is what you pass to the `Agent` initializer:

```swift
func standardInputChecks(maxLength: Int = 5_000) -> [any InputGuardrail] {
    [
        .notEmpty(),
        .maxLength(maxLength),
        .custom("no_scripts") { input in
            input.contains("<script")
                ? .tripwire(message: "Scripts not allowed")
                : .passed()
        }
    ]
}

let agent = try Agent(
    tools: [],
    instructions: "…",
    inputGuardrails: standardInputChecks(maxLength: 2_000)
)
```

An array of guards is **not** itself a guard — use `[any InputGuardrail]`
as the helper's return type, not `some InputGuardrail`.

## Handling `GuardrailError`

Both tripwires surface as ``GuardrailError`` cases:

```swift
do {
    let result = try await agent.run(input)
} catch let error as GuardrailError {
    switch error {
    case let .inputTripwireTriggered(name, message, _):
        print("Input guardrail '\(name)' blocked: \(message ?? "")")
    case let .outputTripwireTriggered(name, agentName, message, _):
        print("Output guardrail '\(name)' on '\(agentName)' blocked: \(message ?? "")")
    default:
        break
    }
}
```

See <doc:ErrorHandling> for the full error taxonomy and recovery patterns.

## See also

- ``InputGuardrail``
- ``OutputGuardrail``
- ``InputGuard``
- ``OutputGuard``
- ``GuardrailResult``
- ``GuardrailError``
- ``GuardrailRunner``
