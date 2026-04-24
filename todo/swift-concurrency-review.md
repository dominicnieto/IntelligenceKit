# Swift Concurrency Review Tracker

Source review: `.context/attachments/pasted_text_2026-04-24_09-17-59.txt`

## Remaining Concurrency Surface

- Open tracker items: `2`
- Lower-priority follow-ups: `4`
- `@unchecked Sendable` declarations remaining in `Sources/`: `134`
- `nonisolated(unsafe)` declarations remaining in `Sources/`: `5`

Notes:
- The raw `@unchecked Sendable` count is broad and includes type-erasure / opaque payload wrappers inherited from the port; it is a surface-area counter, not a severity ranking.
- The `nonisolated(unsafe)` count is small and concentrated in the warning logging subsystem.
- Hard API breaks are acceptable if they produce a cleaner Swift-native concurrency model.

Status legend:
- `[x]` done
- `[ ]` pending
- `[-]` acknowledged follow-up / lower priority

## High-impact findings

### [x] 1. `AsyncStreamBroadcaster` unbounded replay buffer
- Status: fixed
- Outcome: replay buffering now stops growing after subscriber attachment for the `StreamTextActor` usage, with targeted tests added.

### [x] 2. `Download.swift` Linux tuple-assignment / cancellation bridge
- Status: fixed
- Outcome: Linux tuple assignment corrected and callback-based `URLSessionDataTask` cancellation bridged into Swift task cancellation.

### [x] 3. Unsynchronized globals in `ResolveModel.swift`
- Status: fixed by removal
- Outcome: removed `globalDefaultProvider` and `disableGlobalProviderForStringResolution` instead of synchronizing them; string model resolution no longer depends on ambient global provider state.

### [x] 4. `EventSourceParserStream.makeStream` terminate-path race
- Status: resolved by replacement, not local refactor
- Outcome:
  - removed the in-house `EventSourceParser` module instead of modernizing its terminate path
  - adopted `mattt/EventSource` `1.4.1` as the SSE parser dependency
  - localized SSE parsing to a package-scoped helper in `AISDKProviderUtils`
  - production SSE consumers now use the upstream parser boundary instead of the old split-state wrapper

### [x] 5. `StreamTextActor` hand-rolled task-group pattern / unstructured top-level task
- File: `Sources/SwiftAISDK/GenerateText/StreamTextActor.swift`
- Status: fixed
- Outcome:
  - `StreamText` now explicitly owns startup of the actor run loop; `StreamTextActor` no longer self-starts with an unstructured top-level task
  - per-tool task bookkeeping and the intermediate coordinator mailbox were removed in favor of a step-owned `withThrowingTaskGroup`
  - each active provider step now has a single owned `currentStepTask`, so user stop cancels the whole step and its child tool work through structured concurrency
  - approval handling, dynamic tool scheduling, `.abort` before final `.finish`, and step/result semantics were preserved under the new ownership model

## Lower-impact findings

### [ ] 6. `@unchecked Sendable` cleanup / invariant tightening
- Detailed audit: `todo/unchecked-sendable-audit.md`
- Files:
  - `Sources/SwiftAISDK/Streams/AsyncIterableStream.swift`
  - `Sources/SwiftAISDK/UI/Processing/ProcessUIMessageStream.swift`
  - `Sources/SwiftAISDK/UIMessageStream/CreateUIMessageStream.swift`
  - `Sources/SwiftAISDK/UIMessageStream/ReadUIMessageStream.swift`
  - `Sources/SwiftAISDK/UIMessageStream/TeeAsyncThrowingStream.swift`
  - remaining broader stream / pipeline / transport work
- Problem:
  - port-shaped stream/runtime controllers were still using mutable classes, locks, and sync mutation APIs
  - some `@unchecked Sendable` annotations were unnecessary facades over already-isolated state
- Outcome:
  - the `EventSourceParser` part of this item was resolved by removing that module entirely
  - completed the first architecture-first refactor slice for the UI/stream runtime:
    - `UIMessageStreamWriter.write(_:)` and `.merge(_:)` are now async-first mutation APIs
    - `StreamingUIMessageState` is now actor-owned state instead of a shared mutable class
    - `CreateUIMessageStream` and `ReadUIMessageStream` now use actor coordinators instead of lock-backed controllers
    - `teeAsyncThrowingStream` now uses an actor distributor
    - `AsyncIterableStream` is now a plain `Sendable` struct; the remaining unchecked surface in that file is `AnySendableError`
  - completed the second architecture-first slice for MCP client / transport runtime state:
    - `DefaultMCPClient`, `HttpMCPTransport`, `SseMCPTransport`, and `MockMCPTransport` are now actor-owned coordinators instead of lock-backed `@unchecked Sendable` classes
    - the public transport surface no longer exposes mutable `onclose` / `onerror` / `onmessage` callback properties; it now uses one async event registration boundary
    - `MCPClient.onElicitationRequest(...)` is now `async throws` so handler registration happens on the same isolation boundary as request state
    - `MockMCPTransport` test support now uses async message snapshots and explicit server-message injection instead of reaching into callback properties
  - focused MCP suites passed after the refactor:
    - `swift test --filter MCPClientTests`
    - `swift test --filter HttpMCPTransportTests`
    - `swift test --filter SseMCPTransportTests`
    - `swift test --filter MockMCPTransportTests`
  - raw unchecked count reduction from the MCP slice: `138 -> 134`
  - follow-up intentionally deferred to the logger / `swift-log` migration:
    - MCP transport events now surface sendable error wrappers carrying message text rather than the original concrete error objects
    - this is acceptable for the current client/tests, which only need reporting text, but it is still an API-shape change for direct transport consumers
    - track the eventual redesign under `Harden warning-observer tests against cross-suite interference`, where the broader logging / error-reporting boundary will be revisited
  - focused suites covering create/read/process/finish/UI stream behavior and `AsyncIterableStream` passed after the refactor
  - remaining `@unchecked Sendable` review still applies elsewhere, but this establishes the reusable pattern for the rest of item 6:
    - mutable runtime state behind one isolation boundary
    - async mutation edges instead of sync methods hiding locks
    - thin outer facades / value wrappers
    - centralized task, continuation, and cancellation ownership
  
### [ ] 7. Structured vs unstructured task cleanup
- Problem: several places still use `Task { ... }` as an isolation hop / background follow-up where structured concurrency may be clearer and safer.
- Note: this overlaps with item 5 and should be tackled opportunistically when touching those call sites.

### [-] 8. `TimeoutAbortSignalController` modernization
- Problem: lock-backed state is correct but could eventually move to a more modern primitive if/when you want a broader synchronization cleanup.
- Priority: low

### [-] 9. `ResolvablePromise` simplification
- Problem: current implementation works but is more complex than needed.
- Priority: low

### [-] 10. Actor reentrancy conventions in `StreamTextActor`
- Status: reviewed, no concrete bug identified
- Keep the current “re-check stop/cancel after awaits” discipline explicit in future edits.

### [-] 11. Test framework migration
- Problem: concurrency-related tests are still a mix of styles.
- Suggested direction: keep moving toward Swift Testing when touching concurrency suites.

## Additional concurrency cleanup completed after the original review

### [x] Removed `globalDefaultTelemetryTracer`
- Outcome: telemetry tracer selection is now explicit via `TelemetrySettings(tracer:)` or falls back to `noopTracer`.

### [x] Removed per-feature warning hook globals
- Removed:
  - `logWarningsForTranscribe`
  - `logWarningsForGenerateSpeech`
- Outcome: production code now calls `logWarnings(...)` directly; tests observe warnings through centralized `logWarningsObserver`.

### [ ] Harden warning-observer tests against cross-suite interference
- Files:
  - `Tests/SwiftAISDKTests/GenerateSpeech/GenerateSpeechTests.swift`
  - `Tests/SwiftAISDKTests/Transcribe/TranscribeTests.swift`
  - audit nearby warning-observer tests such as `RerankTests`
- Problem:
  - some suites now observe warnings through the shared global `logWarningsObserver` without the stronger token-scoped filtering used in `GenerateImage`, `GenerateVideo`, and `GenerateObject`
  - this can produce first-run flaky counts during full-suite execution when unrelated warning traffic is observed in the same window
- Suggested direction:
  - align the remaining suites to the token-filtered `LogWarningsTestLock.currentOwnerID()` pattern
  - likely redesign later rather than keeping the current global observer pattern as the long-term shape
  - use `SwiftAgent` as the architectural reference point here:
    - explicit observability boundary
    - injected recorder / interceptor / sink style test capture
    - instance-scoped test observation instead of process-global observer state
  - this looks more like a port-shaped test-hook artifact than a Swift-first long-term design
  - fold the MCP transport event error surface into the logger / `swift-log` migration:
    - revisit whether transport events should keep a message-only sendable wrapper or emit a more structured sendable error payload once the logging/error-reporting boundary is redesigned
    - do not treat this as a separate MCP runtime-state refactor unless direct transport consumers start needing typed error inspection before the logging migration

## Current remaining shared-state list

### Already synchronized and lower concern
- `AI_SDK_LOG_WARNINGS`
  - `Sources/SwiftAISDK/Logger/LogWarnings.swift:78`
- `logWarningsObserver`
  - `Sources/SwiftAISDK/Logger/LogWarnings.swift:97`
  - note: still a shared global test hook; current issue is test isolation hardening, not production correctness

### Not a problem
- `@TaskLocal` shared context
  - `Sources/GatewayProvider/GatewayEnvironment.swift:21`

## What’s next

Next target: **Finding 6 — `@unchecked Sendable` cleanup / invariant tightening**.

Why this is next:
- it is now the largest remaining migration surface directly tied to Swift 6.2 concurrency correctness
- the first UI/stream architecture slice is complete, so the next highest-value cleanup is applying the same pattern to the remaining mutable runtime-state subsystems
- the warning-observer todo is real but test-only and not the main production concurrency migration risk

Immediate follow-up within item 6:
- remaining stream / pipeline coordinators such as `RunToolsTransformation`
- utility runtime state such as `DelayedPromise`, `ResolvablePromise`, and `SerialJobExecutor`
- keep the MCP transport error-typing follow-up deferred to the logging / `swift-log` migration noted above, not as a separate item-6 runtime-state slice unless requirements change
