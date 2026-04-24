# Swift Concurrency Review Tracker

Source review: `.context/attachments/pasted_text_2026-04-24_09-17-59.txt`

## Remaining Concurrency Surface

- Open tracker items: `3`
- Lower-priority follow-ups: `4`
- `@unchecked Sendable` declarations remaining in `Sources/`: `143`
- `nonisolated(unsafe)` declarations remaining in `Sources/`: `5`

Notes:
- The raw `@unchecked Sendable` count is broad and includes type-erasure / opaque payload wrappers inherited from the port; it is a surface-area counter, not a severity ranking.
- The `nonisolated(unsafe)` count is small and concentrated in the warning logging subsystem.

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

### [ ] 5. `StreamTextActor` hand-rolled task-group pattern / unstructured top-level task
- File: `Sources/SwiftAISDK/GenerateText/StreamTextActor.swift`
- Problem:
  - tool execution is managed with a dictionary of `Task`s instead of structured concurrency
  - `ensureStarted()` spawns `run()` with an unstructured `Task`
- Suggested direction:
  - replace in-flight tool task bookkeeping with `withTaskGroup` or another structured child-task pattern
  - make caller cancellation flow through the stream pipeline instead of relying on manual stop/cancel handling alone

## Lower-impact findings

### [ ] 6. `@unchecked Sendable` cleanup / invariant tightening
- Files:
  - `Sources/SwiftAISDK/Streams/AsyncIterableStream.swift`
  - `Sources/SwiftAISDK/...` `AnySendableError`
- Problem:
  - some `@unchecked Sendable` annotations look unnecessary
  - `EventSourceParser` relied on a serial-access invariant that should be documented or enforced
- Outcome:
  - the `EventSourceParser` part of this item was resolved by removing that module entirely
  - remaining `@unchecked Sendable` review still applies elsewhere, but the SSE parser-specific concern is gone

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

Next target: **Finding 5 — `StreamTextActor` hand-rolled task-group pattern / unstructured top-level task**.

Why this is next:
- it is now the largest remaining high-impact concurrency item from the original review
- it affects cancellation flow and task structure in a core streaming path
- the new warning-observer todo is real but test-only and not tied to the just-finished `EventSource` work
