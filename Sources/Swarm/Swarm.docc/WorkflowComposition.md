# Workflow Composition

Patterns for chaining, branching, retrying, and observing multi-agent pipelines.

## Overview

``Workflow`` is a value-type DSL: each builder method returns a new workflow,
so you can split a pipeline into reusable fragments or configure variants
without mutating a shared value. Call ``Workflow/run(_:)`` to get a final
``AgentResult`` or ``Workflow/stream(_:)`` to observe lifecycle events as
they happen.

## Sequential composition

``Workflow/step(_:)`` appends an agent to run after the current step. Each
agent receives the previous step's output as its input:

```swift
let result = try await Workflow()
    .step(researchAgent)
    .step(outlineAgent)
    .step(writerAgent)
    .run("Write about Swift concurrency")
```

## Parallel composition

``Workflow/parallel(_:merge:)`` runs several agents on the **same input**
concurrently. Their outputs are combined according to the
``Workflow/MergeStrategy``:

```swift
let result = try await Workflow()
    .parallel([technicalAgent, businessAgent, userAgent], merge: .indexed)
    .step(synthesizerAgent)
    .run("Evaluate new feature proposal")
```

### Merge strategies

- ``Workflow/MergeStrategy/structured`` — JSON object keyed by index,
  `{"0":"…","1":"…"}`. Easy to parse downstream.
- ``Workflow/MergeStrategy/indexed`` — human-readable numbered list,
  `[0]: …\n[1]: …`.
- ``Workflow/MergeStrategy/first`` — whichever agent finishes first wins.
  The other agents still run to completion; their outputs are discarded.
- ``Workflow/MergeStrategy/custom(_:)`` — supply a closure over
  `[AgentResult]` to produce any string you want:

  ```swift
  .parallel([a, b, c], merge: .custom { results in
      results.map { "- \($0.output)" }.joined(separator: "\n")
  })
  ```

## Dynamic routing

``Workflow/route(_:)`` picks the next agent at runtime based on the current
input. Returning `nil` raises ``WorkflowError/routingFailed(reason:)``:

```swift
let result = try await Workflow()
    .route { input in
        if input.contains("code") { return codeAgent }
        if input.contains("design") { return designAgent }
        return generalAgent
    }
    .run("Review this code snippet")
```

## Iteration

``Workflow/repeatUntil(maxIterations:_:)`` repeats the pipeline, feeding each
result's output back as the next iteration's input, until the condition
returns `true` or `maxIterations` is hit:

```swift
let result = try await Workflow()
    .step(refinerAgent)
    .repeatUntil(maxIterations: 10) { result in
        result.output.contains("FINAL") || result.iterationCount >= 5
    }
    .run("Write a compelling headline")
```

The closure receives the full ``AgentResult`` — `output`, `iterationCount`,
`toolCalls`, and `metadata` are all fair game for the stop condition.

## Timeouts

``Workflow/timeout(_:)`` caps total wall-clock time. Exceeding it throws
``AgentError/timeout(duration:)``:

```swift
let result = try await Workflow()
    .step(potentiallySlowAgent)
    .timeout(.seconds(30))
    .run("Complex analysis task")
```

## Observation

``Workflow/observed(by:)`` attaches an ``AgentObserver`` that receives events
during execution — lifecycle, agent output, tool calls, errors:

```swift
let result = try await Workflow()
    .step(agentA)
    .step(agentB)
    .observed(by: loggingObserver)
    .run("Task input")
```

For live consumption, use ``Workflow/stream(_:)`` instead — it emits the
lifecycle events to an async stream without needing a custom observer type:

```swift
for try await event in workflow.stream("Task input") {
    switch event {
    case .lifecycle(.started):
        print("Workflow started")
    case .lifecycle(.completed(let result)):
        print("Completed: \(result.output)")
    case .lifecycle(.failed(let error)):
        print("Failed: \(error)")
    default: break
    }
}
```

## Durable workflows

``Workflow/durable`` exposes a checkpointing namespace. Configure a
checkpoint policy and a ``WorkflowCheckpointing`` store, then call
`execute(_:resumeFrom:)` instead of `run(_:)`:

```swift
let workflow = Workflow()
    .step(expensiveAgent)
    .step(anotherExpensiveAgent)
    .durable
    .checkpoint(id: "report-2026-04-16", policy: .everyStep)
    .durable
    .checkpointing(myCheckpointStore)

let result = try await workflow.durable.execute("Generate quarterly report")

// Later, resume from the persisted checkpoint:
let resumed = try await workflow.durable.execute(
    "Generate quarterly report",
    resumeFrom: "report-2026-04-16"
)
```

Durable workflows also support a workflow-level `fallback(primary:to:retries:)`
step that retries the primary agent up to `retries` times before handing off
to a backup:

```swift
let workflow = Workflow()
    .durable
    .fallback(primary: primaryAgent, to: backupAgent, retries: 2)
```

## `run(_:)` vs `stream(_:)`

- ``Workflow/run(_:)`` waits until the pipeline finishes and returns one
  `AgentResult`.
- ``Workflow/stream(_:)`` emits `lifecycle(.started(input:))`, then
  `lifecycle(.completed(result:))` on success or `lifecycle(.failed(error:))`
  on failure. Use it when you want to surface progress to a UI without
  passing an observer through.

For per-step agent internals (token deltas, tool-call events), use
``Workflow/observed(by:)`` and implement ``AgentObserver`` — the workflow
passes your observer down to each agent's `run(_:session:observer:)`.

## Errors

Workflow-specific failures surface as ``WorkflowError`` (routing failures,
checkpoint issues, invalid graph). Agent-level failures propagate as
``AgentError``. Both conform to `LocalizedError` — see <doc:ErrorHandling>.
