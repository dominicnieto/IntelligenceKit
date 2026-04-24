# `@unchecked Sendable` Audit

Date: 2026-04-24

Scope:
- audited `Sources/` using the `swift-concurrency` and `swift-concurrency-pro` review criteria
- inventory source: `grep -RIn "@unchecked Sendable" Sources`
- current raw count: `134`

## Summary

The raw count is high, but it is not one homogeneous problem.

Most important takeaway:
- the first work should not be “delete the largest number of annotations”
- the first work should be “remove `@unchecked Sendable` from mutable runtime state that sits on active stream / transport / task boundaries”
- Hard API breaks are acceptable if they produce a cleaner Swift-native concurrency model.

Completed first-wave slice:
- refactored the `UIMessageStream` runtime (`ProcessUIMessageStream`, `CreateUIMessageStream`, `ReadUIMessageStream`, `TeeAsyncThrowingStream`) to use actor-owned state/coordinators and async mutation APIs
- converted `AsyncIterableStream` into a plain `Sendable` struct
- raw count reduction from this wave: `143 -> 138`
- remaining unchecked item in the touched stream facade: `AnySendableError` in `AsyncIterableStream`

Completed second-wave slice:
- refactored the MCP runtime (`MCPClient`, `HttpMCPTransport`, `SseMCPTransport`, `MockMCPTransport`) to use actor-owned client/transport state machines
- removed the mutable transport callback-property surface in favor of one async event registration boundary
- changed `MCPClient.onElicitationRequest(...)` to `async throws`
- updated MCP test support to use async message snapshots and explicit server-message injection
- raw count reduction from this wave: `138 -> 134`
- focused suites passed:
  - `swift test --filter MCPClientTests`
  - `swift test --filter HttpMCPTransportTests`
  - `swift test --filter SseMCPTransportTests`
  - `swift test --filter MockMCPTransportTests`

Count concentration by target:
- `SwiftAISDK`: `40`
- `AISDKZodAdapter`: `38`
- `AISDKProvider`: `30`
- `AISDKProviderUtils`: `15`
- `GatewayProvider`: `7`
- `AnthropicProvider`: `2`
- `OpenAIProvider`: `1`
- `AISDKJSONSchema`: `1`

Largest single-file concentrations:
- `Sources/AISDKZodAdapter/Zod3/Zod3Types.swift`: `37`
- `Sources/AISDKProviderUtils/Schema/Schema.swift`: `10`
- `Sources/SwiftAISDK/Error/MCPClientOAuthError.swift`: `5`

Important note:
- at least `16` of the declarations are explicitly documented as “match TypeScript’s unknown type” or another opaque payload mirror
- those are real cleanup targets, but they are mostly API-shape debt, not the first concurrency-correctness fires

## Recommended Precedence

This is the order I would tackle for the migration.

### 1. Live mutable runtime state in stream / UI / pipeline code

Why first:
- highest chance of hiding real race conditions
- sits on active async boundaries, continuations, tasks, callbacks, or mutable shared state
- directly affects product behavior under cancellation, multi-subscriber use, and streaming

Files:
- `Sources/SwiftAISDK/Streams/AsyncIterableStream.swift`
- `Sources/SwiftAISDK/UI/Processing/ProcessUIMessageStream.swift`
- `Sources/SwiftAISDK/UIMessageStream/ReadUIMessageStream.swift`
- `Sources/SwiftAISDK/UIMessageStream/CreateUIMessageStream.swift`
- `Sources/SwiftAISDK/UIMessageStream/TeeAsyncThrowingStream.swift`
- `Sources/SwiftAISDK/GenerateText/RunToolsTransformation.swift`
- `Sources/SwiftAISDK/GenerateText/StreamText.swift`
- `Sources/SwiftAISDK/GenerateText/StreamTextEventRecorder.swift`
- `Sources/SwiftAISDK/GenerateObject/StreamObjectResult.swift`
- `Sources/SwiftAISDK/Agent/Agent.swift`

Why these are risky:
- mutable reference types are crossing task boundaries
- several are controller/state objects used from `Task {}` closures or stream termination hooks
- these are exactly the places where `@unchecked Sendable` can hide a real ownership problem instead of a merely inconvenient compiler diagnostic

Preferred redesign direction:
- move mutable state behind actors where practical
- keep outer result/container types immutable and plain `Sendable`
- avoid “controller class + lock + async callbacks” when actor-owned state is clearer

Status after first wave:
- completed for the `UIMessageStream` cluster and the `AsyncIterableStream` facade
- architecture template validated by focused suites covering create/read/process/finish/UI stream behavior and `AsyncIterableStream`
- remaining files in this bucket should follow the same template:
  - async mutation edges instead of sync methods hiding locks
  - one explicit isolation boundary for mutable runtime state
  - centralized continuation / task / cancellation ownership
  - thin outer facades or value wrappers

### 2. MCP client / transport state machines

Status:
- completed
- the four production MCP runtime coordinators no longer use `@unchecked Sendable`
- this validated the same migration template on a network-facing state machine boundary, not just stream/UI code

Why second:
- network transport code mixes locks, callbacks, task handles, reconnect state, and externally-invoked closures
- this is a classic place where `@unchecked Sendable` papers over a state-machine design that should have an explicit isolation boundary

Files:
- `Sources/SwiftAISDK/Tool/MCP/MCPClient.swift`
- `Sources/SwiftAISDK/Tool/MCP/HttpMCPTransport.swift`
- `Sources/SwiftAISDK/Tool/MCP/SseMCPTransport.swift`
- `Sources/SwiftAISDK/Tool/MCP/MockMCPTransport.swift`

Why these are risky:
- mutable connection/session/reconnect state
- collections of in-flight tasks and response handlers
- cross-boundary callback plumbing (`onclose`, `onerror`, `onmessage`)

Preferred redesign direction:
- actor-backed transport/client state
- lexical ownership of request tasks where possible
- remove lock-managed mutable dictionaries/arrays from sendable classes

Next target after MCP:
- `Sources/SwiftAISDK/GenerateText/RunToolsTransformation.swift`
- then the utility runtime-state cluster (`DelayedPromise`, `ResolvablePromise`, `SerialJobExecutor`, timeout/cancellation helpers)

### 3. Core utility synchronization wrappers used across the package

Why third:
- smaller blast radius than the streaming/MCP layers
- high leverage because many higher-level types depend on them
- several of these are probably valid lock-backed implementations today, but they still keep `@unchecked Sendable` in the center of the package

Files:
- `Sources/SwiftAISDK/Util/DelayedPromise.swift`
- `Sources/SwiftAISDK/Util/CreateResolvablePromise.swift`
- `Sources/SwiftAISDK/Util/SerialJobExecutor.swift`
- `Sources/SwiftAISDK/Util/TimeoutAbortSignalController.swift`
- `Sources/SwiftAISDK/Util/Download/Download.swift`
- `Sources/SwiftAISDK/Logger/LogWarnings.swift`
- `Sources/AISDKJSONSchema/JSONSchemaGenerator.swift`
- `Sources/AnthropicProvider/GetCacheControl.swift`

Why these matter:
- some are lock-backed and probably safe, but still rely on manual invariants
- they set the tone for the rest of the codebase
- replacing these with actors or `Mutex`-style primitives reduces future pressure to add more unchecked sendability

Preferred redesign direction:
- actors where the abstraction is stateful and async-facing
- modern synchronous locking primitive only where a tiny synchronous state holder is the right design
- document any remaining justified lock-based sendability invariants

### 4. Schema / Zod architecture pass

Why fourth:
- this is the biggest count reducer by far
- but it is a broader architecture cleanup, not the first runtime-risk item

Files:
- `Sources/AISDKProviderUtils/Schema/Schema.swift`
- `Sources/AISDKZodAdapter/Zod3/Zod3Types.swift`
- `Sources/AISDKZodAdapter/Zod3/Zod3Options.swift`

Why this is a separate wave:
- these files are heavily port-shaped
- a large part of the unchecked sendability comes from class-heavy schema graphs and type-erased validation inputs
- trying to “chip away” at these one annotation at a time is likely to waste effort

Preferred redesign direction:
- decide whether these schema/Zod types should be:
- immutable value types
- actor-isolated caches/loaders
- or intentionally non-sendable internals hidden behind sendable facades

Recommended approach:
- treat this as one deliberate subsystem redesign
- do not optimize for raw count alone

Important boundary learned from the first wave:
- do not mix this runtime-state pattern with the later opaque-payload cleanup
- `AnySendableError` and TypeScript-`unknown` mirrors are still separate API-shape work even when they live near stream code

### 5. Immutable wrappers and adapters that should probably become plain `Sendable`

Why fifth:
- many of these look like easy wins once the more dangerous mutable state is addressed
- they appear to be immutable wrappers where `@unchecked Sendable` is mostly inherited from the original port shape

Files:
- `Sources/OpenAIProvider/OpenAIConfig.swift`
- `Sources/AnthropicProvider/AnthropicMessagesLanguageModel.swift`
- `Sources/AnthropicProvider/AnthropicMessagesLanguageModel.swift` (`AnthropicMessagesConfig`)
- `Sources/SwiftAISDK/Middleware/WrapLanguageModel.swift`
- `Sources/SwiftAISDK/Model/ResolveModel.swift`
- `Sources/SwiftAISDK/Telemetry/NoopTracer.swift`
- `Sources/SwiftAISDK/Test/MockImageModelV3.swift`
- `Sources/SwiftAISDK/Test/MockLanguageModelV2.swift`
- `Sources/SwiftAISDK/Test/MockLanguageModelV3.swift`
- `Sources/SwiftAISDK/Test/MockVideoModelV3.swift`

Why these are lower urgency:
- they do not look like the most race-prone code paths
- many may collapse to normal `Sendable` once surrounding protocol and closure types are tightened

### 6. Generated file / result wrapper reference types

Why sixth:
- real cleanup opportunity, but mostly API-shape and storage-choice work
- lower risk than stream controllers and transport state

Files:
- `Sources/SwiftAISDK/GenerateText/GeneratedFile.swift`
- `Sources/SwiftAISDK/GenerateSpeech/GeneratedAudioFile.swift`
- `Sources/SwiftAISDK/GenerateSpeech/GenerateSpeechResult.swift`
- `Sources/SwiftAISDK/Transcribe/TranscribeResult.swift`

Why these are separate:
- some are reference types only to support lazy conversion/caching
- they may be better as immutable structs with eager normalization, or as actor/lock-backed storage if lazy behavior truly matters

### 7. Opaque payload / “TypeScript unknown” public API mirrors

Why last:
- these are important, but they are not primarily a concurrency-architecture problem
- they are public API design debt caused by `Any?` / opaque body payloads

Files:
- `Sources/AISDKProvider/LanguageModel/V2/LanguageModelV2.swift`
- `Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3.swift`
- `Sources/AISDKProvider/SpeechModel/SpeechModelV2.swift`
- `Sources/AISDKProvider/SpeechModel/SpeechModelV3.swift`
- `Sources/AISDKProvider/EmbeddingModel/EmbeddingModelV2.swift`
- `Sources/AISDKProvider/EmbeddingModel/EmbeddingModelV3.swift`
- `Sources/AISDKProvider/TranscriptionModel/TranscriptionModelV2.swift`
- `Sources/AISDKProvider/TranscriptionModel/TranscriptionModelV3.swift`
- `Sources/AISDKProvider/RerankingModel/RerankingModelV3.swift`
- `Sources/SwiftAISDK/Types/SpeechModelResponseMetadata.swift`
- `Sources/SwiftAISDK/Rerank/RerankResult.swift`
- `Sources/SwiftAISDK/Error/MCPClientError.swift`
- `Sources/SwiftAISDK/Error/MCPClientOAuthError.swift`
- selected provider error types in `Sources/AISDKProvider/Errors/`
- selected gateway error types in `Sources/GatewayProvider/`

Why these are different:
- the main issue is `Any` and loosely-typed payload surfaces
- a real fix likely means replacing `Any?` with `JSONValue`, a typed payload enum, or a sendable type-erased box with explicit invariants
- that is a public API cleanup project, not a tactical concurrency sweep

## Easiest Wins

If the goal is “reduce count quickly with low semantic risk”, start here instead:

1. immutable config / adapter wrappers
- `OpenAIConfig`
- `AnthropicMessagesConfig`
- `WrappedLanguageModel`
- `LanguageModelV2ToV3Adapter`
- `EmbeddingModelV2ToV3Adapter`
- `NoopSpan`
- `NoopTracer`

2. test-only model wrappers under `Sources/SwiftAISDK/Test`
- low production risk
- likely removable with tighter stored-property typing

3. tiny lock-backed state holders
- `TimeoutAbortSignalController`
- `SchemaCache`
- `CacheControlValidator`

These are not the highest-priority correctness items, but they are the lowest-friction cleanup candidates.

## Hardest / Most Architectural

These are the places where the count is high or the design is port-shaped enough that the right move is a subsystem redesign:

1. `AISDKZodAdapter/Zod3/Zod3Types.swift`
- biggest single-file concentration
- likely requires redesigning class-heavy schema representation rather than annotation whack-a-mole

2. `AISDKProviderUtils/Schema/Schema.swift`
- mixes sendable facades with `Any` validation and lock-backed lazy storage
- needs a coherent sendability story for schema values and validators

3. MCP transport/client layer
- state machines, callbacks, reconnect logic, and in-flight task storage

4. UI message stream controllers
- mutable state objects flowing through async closures and stream termination hooks

## Suggested Attack Plan

If the goal is best migration value, I would do it in this order:

1. live stream / UI / pipeline state
2. MCP client + transports
3. shared utility synchronization wrappers
4. schema + Zod subsystem redesign
5. immutable wrapper cleanup
6. generated file/result wrappers
7. opaque `Any` / public API payload cleanup

If the goal is fastest count reduction, I would do it in this order:

1. immutable wrappers and adapters
2. test mocks
3. tiny lock-backed helpers
4. generated file/result wrappers
5. stream/UI/MCP state
6. schema/Zod
7. public API `Any` payloads

## Recommendation

For this repo, I would optimize for migration correctness, not for the raw count dashboard.

That means:
- tackle the mutable runtime state first
- leave the “TypeScript unknown” API mirrors for a later public-surface cleanup
- treat the Zod/schema cluster as one architecture item, not dozens of independent micro-fixes
