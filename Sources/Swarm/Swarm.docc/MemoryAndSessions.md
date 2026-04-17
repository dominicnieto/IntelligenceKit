# Memory and Sessions

How Swarm agents remember — the difference between memory and sessions, how
to pick a memory implementation, and how to bring your own.

## Overview

Swarm distinguishes two concepts:

- **Session** is the source of truth for conversation history — the actual
  turns exchanged between user and agent. Sessions conform to ``Session``
  (see ``InMemorySession`` and ``PersistentSession``).
- **Memory** provides retrieved context for the current turn — recent
  messages, summaries of old history, or semantically-similar snippets from
  a knowledge base. Memory conforms to ``Memory``.

Agents store conversations in the session and consult memory to assemble the
prompt. If you only need one, you almost always want a session.

## Picking a `Memory` implementation

| Implementation | Pick when |
|---|---|
| ``ConversationMemory`` | Simple chat; fixed message cap; no embeddings. |
| ``SlidingWindowMemory`` | You need precise token budgeting; context window is tight. |
| ``SummaryMemory`` | Long conversations; older detail can be lost safely. |
| ``HybridMemory`` | Long conversations where some older detail matters. |
| ``PersistentMemory`` | Multi-session apps; survive restarts. |
| ``VectorMemory`` | RAG over a knowledge base; semantic recall. |

Factory methods on the ``Memory`` protocol construct each type:

```swift
let simple: any Memory    = .conversation(maxMessages: 50)
let bounded: any Memory   = .slidingWindow(maxTokens: 8_000)
let summarized: any Memory = .summary(
    configuration: .init(recentMessageCount: 20)
)
let hybrid: any Memory    = .hybrid(
    configuration: .init(shortTermMaxMessages: 30)
)
let persistent: any Memory = .persistent(
    backend: InMemoryBackend(),   // or try SwiftDataBackend(...) on Apple platforms
    conversationId: "user-123"
)
```

Pass the result to an ``Agent`` via its initializer's `memory:` parameter:

```swift
let agent = try Agent(
    tools: [],
    instructions: "You are a helpful assistant.",
    memory: .conversation(maxMessages: 100)
)
```

## Persistence on Apple platforms

``SwiftDataBackend`` (macOS 14 / iOS 17+) persists messages via SwiftData.
Pair it with ``PersistentMemory``:

```swift
let backend = try SwiftDataBackend.persistent()
let memory = PersistentMemory(backend: backend)

let agent = try Agent(
    tools: [],
    instructions: "...",
    memory: memory
)
```

For tests and ephemeral flows, ``InMemoryBackend`` gives you the same API
without any storage.

## Vector / RAG

``VectorMemory`` requires an ``EmbeddingProvider`` — bring your own,
implementing the protocol's `embed(_:)` requirement. No provider ships in
`Swarm` itself; implementations live in the integrations modules or your
app.

```swift
let memory: any Memory = .vector(
    embeddingProvider: myEmbedder,
    similarityThreshold: 0.75,
    maxResults: 5
)
```

## Custom `Memory` conformance

`Memory` is an `Actor` protocol with six requirements: `count`, `isEmpty`,
`add`, `context(for:tokenLimit:)`, `allMessages`, `clear`. A minimal
implementation:

```swift
public actor NotesMemory: Memory {
    private var messages: [MemoryMessage] = []

    public var count: Int { messages.count }
    public var isEmpty: Bool { messages.isEmpty }

    public func add(_ message: MemoryMessage) async {
        messages.append(message)
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        MemoryMessage.formatContext(messages, tokenLimit: tokenLimit)
    }

    public func allMessages() async -> [MemoryMessage] { messages }

    public func clear() async { messages.removeAll() }
}
```

``MemoryMessage/formatContext(_:tokenLimit:tokenEstimator:)`` handles
most-recent-first truncation inside a token budget — use it for any
implementation that returns raw message history.

## Formatting context

Pass your messages through `MemoryMessage.formatContext` to get a
prompt-ready string within a token bound. The default token estimator is
``CharacterBasedTokenEstimator/shared``; supply your own via the
`tokenEstimator:` parameter when you need accuracy.

```swift
let prompt = MemoryMessage.formatContext(
    await memory.allMessages(),
    tokenLimit: 4_000
)
```

## Errors

Memory operations don't throw by default — their APIs are `async`, not
`async throws`. Persistent backends may surface their own errors via their
backend type. See the concrete implementations for specifics.

## See also

- ``Agent``
- ``Session`` — the parallel concept: source of truth for conversation history
- <doc:ErrorHandling>
