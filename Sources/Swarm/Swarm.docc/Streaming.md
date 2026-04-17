# Streaming

Consuming and composing streams of ``AgentEvent``.

## Overview

``Agent/stream(_:session:observer:)`` and ``Workflow/stream(_:)`` return
`AsyncThrowingStream<AgentEvent, Error>`. Every event belongs to one of a few
categories: **lifecycle** (`started`, `completed`, `failed`), **output**
(`thinking`, `delta`, `text`), **tool** (`started`, `completed`). For live
UI, you usually care about thinking and text chunks; for observability,
lifecycle; for auditing, tool events.

Swarm extends `AsyncThrowingStream<AgentEvent, Error>` with ~30 operators in
`Sources/Swarm/Core/StreamOperations.swift`. This article groups them by
what they're for.

## Extracting specific channels

```swift
let stream = agent.stream("Research swift concurrency")

for try await thought in stream.thoughts {
    print("thinking:", thought)
}

for try await call in stream.toolCalls {
    print("tool started:", call.toolName)
}

for try await result in stream.toolResults {
    print("tool returned:", result)
}
```

``AsyncThrowingStream/thoughts``, ``AsyncThrowingStream/toolCalls``,
``AsyncThrowingStream/toolResults`` are one-liner accessors over the more
general `filter` / `map` primitives below — use them when you know which
channel you want.

## Filtering and mapping

```swift
// Keep only thinking events
let thinking = agent.stream("...").filterThinking()

// Keep only tool events (started + completed)
let toolActivity = agent.stream("...").filterToolEvents()

// Arbitrary predicate
let longThoughts = agent.stream("...").filter { event in
    if case let .output(.thinking(thought)) = event {
        return thought.count > 40
    }
    return false
}

// Transform each event
let summaries: AsyncThrowingStream<String, Error> = agent.stream("...").map { event in
    String(describing: event)
}

// map + filter in one pass
let capitalizedThoughts: AsyncThrowingStream<String, Error> =
    agent.stream("...").compactMap { event in
        if case let .output(.thinking(thought)) = event {
            return thought.uppercased()
        }
        return nil
    }
```

``AsyncThrowingStream/mapToThoughts()`` is a shortcut for the thinking-only
compactMap shown above.

## Collecting

```swift
// Everything
let all: [AgentEvent] = try await agent.stream("...").collect()

// Cap on memory use
let firstFive: [AgentEvent] = try await agent.stream("...").collect(maxCount: 5)

// First matching event
let firstCompletion = try await agent.stream("...").first { event in
    if case .lifecycle(.completed) = event { return true }
    return false
}

// Last event (consumes entire stream)
let last = try await agent.stream("...").last()

// Fold into a single value
let totalThinkingChars = try await agent.stream("...").reduce(0) { acc, event in
    if case let .output(.thinking(thought)) = event {
        return acc + thought.count
    }
    return acc
}

// Emit every intermediate fold value (streaming reduce)
for try await runningTotal in agent.stream("...").scan(0, { acc, _ in acc + 1 }) {
    print("events so far:", runningTotal)
}
```

## Taking, dropping, dedup

```swift
let firstThree = agent.stream("...").take(3)
let skipHeader = agent.stream("...").drop(2)

// Drop consecutive duplicates (uses AgentEvent's own isEqual(to:))
let deduped = agent.stream("...").distinctUntilChanged()
```

## Time-based operators

All three take a `Duration`. Pick based on throughput vs latency:

```swift
// Cancel the stream if it runs too long
for try await event in agent.stream("...").timeout(after: .seconds(30)) {
    // throws AgentError.timeout(duration:) if 30s elapses
}

// Collapse rapid updates into the most recent one (UI-friendly)
let settled = agent.stream("...").debounce(for: .milliseconds(100))

// Cap emission rate; first event in each window passes, rest drop
let rateLimited = agent.stream("...").throttle(for: .seconds(1))

// Batch events for downstream processing
for try await batch in agent.stream("...").buffer(count: 10) {
    try await sink.accept(batch)
}
```

## Side-effect hooks

Pass-through operators that let you inspect without consuming:

```swift
let stream = agent.stream("...")
    .onEach { event in logger.debug("event: \(event)") }
    .onComplete { result in metrics.record(result.tokenUsage) }
    .onError { error in logger.error("agent failed: \(error)") }
```

`onEach` runs for every event; `onComplete` fires when the stream emits a
`.lifecycle(.completed(result:))`; `onError` fires on `.lifecycle(.failed(error:))`.
All three return the original stream unchanged.

## Error handling

`catchErrors` converts a thrown error into a final event, allowing the
stream to complete normally:

```swift
let resilient = agent.stream("...").catchErrors { error in
    .lifecycle(.failed(error: .internalError(reason: "recovered: \(error)")))
}
```

For retry-style error handling, see the next section.

## Retry

``AsyncThrowingStream/retry(maxAttempts:delay:factory:)`` wraps a stream
*factory*, not a stream — each attempt calls the factory to get a fresh
stream:

```swift
let resilientStream = AsyncThrowingStream<AgentEvent, Error>.retry(
    maxAttempts: 3,
    delay: .seconds(1)
) {
    agent.stream("Research swift concurrency")
}

for try await event in resilientStream {
    // up to 3 fresh agent.stream(...) attempts, 1 second apart on failure
}
```

The factory closure is called once per attempt. `agent.stream(_:)` is
synchronous (returns an `AsyncThrowingStream`) so do not `await` it.

## Merging multiple streams

```swift
let merged = AgentEventStream.merge(
    parallelAgentA.stream("..."),
    parallelAgentB.stream("..."),
    errorStrategy: .continueAndCollect
)

for try await event in merged {
    // interleaved events from both agents
}
```

``MergeErrorStrategy`` options:
- ``MergeErrorStrategy/continueAndCollect`` (default) — errors from one
  stream become `.lifecycle(.failed)` events; the other streams keep running.
- ``MergeErrorStrategy/failFast`` — first error from any stream aborts the
  merged stream.
- ``MergeErrorStrategy/ignoreErrors`` — errors are silently dropped.

## Testing helpers

Four constructors build predictable streams for unit tests:

```swift
// An immediate empty completion
let e = AgentEventStream.empty()

// A single event then completion
let j = AgentEventStream.just(.lifecycle(.started(input: "hello")))

// A predetermined sequence
let f = AgentEventStream.from([
    .lifecycle(.started(input: "q")),
    .output(.thinking(thought: "…")),
    .lifecycle(.completed(result: stubResult))
])

// An immediate failure
let x = AgentEventStream.fail(AgentError.internalError(reason: "test"))
```

Use these to drive your own operator tests without running an agent.

## See also

- ``Agent``
- ``Workflow``
- ``AgentEvent``
- ``MergeErrorStrategy``
- ``AgentEventStream``
- <doc:ErrorHandling>
