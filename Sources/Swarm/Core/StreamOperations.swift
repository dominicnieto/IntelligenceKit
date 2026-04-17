// StreamOperations.swift
// Swarm Framework
//
// Functional operations on AsyncThrowingStream<AgentEvent, Error> for reactive stream processing.

import Foundation

// MARK: - AgentEvent Stream Operations

/// Functional operators on streams of ``AgentEvent``. See <doc:Streaming> for
/// worked pipelines (filter → collect, retry with backoff, merging, testing
/// helpers).
public extension AsyncThrowingStream where Element == AgentEvent, Failure == Error {
    // MARK: - Property Accessors

    /// Stream of thought strings extracted from `.output(.thinking)` events.
    var thoughts: AsyncThrowingStream<String, Error> {
        mapToThoughts()
    }

    /// Stream of ``ToolCall`` values extracted from `.tool(.started)` events.
    var toolCalls: AsyncThrowingStream<ToolCall, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                if case let .tool(.started(call: call)) = event {
                    continuation.yield(call)
                }
            }
            continuation.finish()
        }
    }

    /// Stream of ``ToolResult`` values extracted from `.tool(.completed)` events.
    var toolResults: AsyncThrowingStream<ToolResult, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                if case let .tool(.completed(call: _, result: result)) = event {
                    continuation.yield(result)
                }
            }
            continuation.finish()
        }
    }

    // MARK: - Retry

    /// Re-runs `factory` up to `maxAttempts` times, waiting `delay` between
    /// attempts, yielding events from the first stream that completes
    /// without throwing.
    /// - Parameter factory: called once per attempt; must return a fresh
    ///   stream (not a re-iteration of an exhausted one)
    static func retry(
        maxAttempts: Int = 3,
        delay: Duration = .zero,
        factory: @escaping @Sendable () async -> AsyncThrowingStream<AgentEvent, Error>
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation): (AsyncThrowingStream<AgentEvent, Error>, AsyncThrowingStream<AgentEvent, Error>.Continuation) = StreamHelper.makeStream()

        let task = Task { @Sendable in
            var attempts = 0
            var lastError: Error?

            while attempts < maxAttempts {
                attempts += 1
                do {
                    let newStream = await factory()
                    for try await event in newStream {
                        continuation.yield(event)
                    }
                    // Stream completed successfully
                    continuation.finish()
                    return
                } catch {
                    lastError = error
                    if attempts < maxAttempts, delay != .zero {
                        try? await Task.sleep(for: delay)
                    }
                }
            }

            // All attempts exhausted
            if let error = lastError {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }

        continuation.onTermination = { @Sendable (_: AsyncThrowingStream<AgentEvent, Error>.Continuation.Termination) in
            task.cancel()
        }

        return stream
    }

    // MARK: - Filtering

    /// Keeps only `.output(.thinking)` events.
    func filterThinking() -> AsyncThrowingStream<AgentEvent, Error> {
        filter { event in
            if case .output(.thinking) = event { return true }
            return false
        }
    }

    /// Keeps only `.tool(...)` events (both started and completed).
    func filterToolEvents() -> AsyncThrowingStream<AgentEvent, Error> {
        filter { event in
            if case .tool = event { return true }
            return false
        }
    }

    /// Keeps only events where `predicate` returns `true`.
    func filter(
        _ predicate: @escaping @Sendable (AgentEvent) -> Bool
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self where predicate(event) {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    // MARK: - Mapping

    /// Applies `transform` to each event, yielding the results as a new stream.
    func map<T: Sendable>(
        _ transform: @escaping @Sendable (AgentEvent) -> T
    ) -> AsyncThrowingStream<T, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                continuation.yield(transform(event))
            }
            continuation.finish()
        }
    }

    /// Shortcut for ``filterThinking()`` followed by extracting the thought
    /// string — yields only the thought text.
    func mapToThoughts() -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                if case let .output(.thinking(thought: thought)) = event {
                    continuation.yield(thought)
                }
            }
            continuation.finish()
        }
    }

    // MARK: - Collection Operations

    /// Accumulates every event into an array.
    func collect() async throws -> [AgentEvent] {
        var results: [AgentEvent] = []
        for try await event in self {
            results.append(event)
        }
        return results
    }

    /// Accumulates up to `maxCount` events, then stops.
    func collect(maxCount: Int) async throws -> [AgentEvent] {
        var results: [AgentEvent] = []
        for try await event in self {
            results.append(event)
            if results.count >= maxCount { break }
        }
        return results
    }

    // MARK: - First/Last

    /// Returns the first event matching `predicate`, or `nil` if the stream
    /// completes without a match.
    func first(
        where predicate: @escaping @Sendable (AgentEvent) -> Bool
    ) async throws -> AgentEvent? {
        for try await event in self where predicate(event) {
            return event
        }
        return nil
    }

    /// Consumes the whole stream and returns the last event, or `nil` if empty.
    func last() async throws -> AgentEvent? {
        var lastEvent: AgentEvent?
        for try await event in self {
            lastEvent = event
        }
        return lastEvent
    }

    // MARK: - Reduce

    /// Folds the stream into a single value by applying `combine` to each event.
    func reduce<T: Sendable>(
        _ initial: T,
        _ combine: @escaping @Sendable (T, AgentEvent) -> T
    ) async throws -> T {
        var result = initial
        for try await event in self {
            result = combine(result, event)
        }
        return result
    }

    // MARK: - Take/Drop

    /// Yields the first `count` events, then completes.
    func take(_ count: Int) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var taken = 0
            for try await event in self {
                continuation.yield(event)
                taken += 1
                if taken >= count { break }
            }
            continuation.finish()
        }
    }

    /// Skips the first `count` events, then yields the rest.
    func drop(_ count: Int) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var dropped = 0
            for try await event in self {
                if dropped < count {
                    dropped += 1
                    continue
                }
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    // MARK: - Timeout

    /// Throws ``AgentError/timeout(duration:)`` if the stream runs longer
    /// than `duration` without completing.
    func timeout(after duration: Duration) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation): (AsyncThrowingStream<AgentEvent, Error>, AsyncThrowingStream<AgentEvent, Error>.Continuation) = StreamHelper.makeStream()

        let timeoutTask = Task {
            try await Task.sleep(for: duration)
            continuation.finish(throwing: AgentError.timeout(duration: duration))
        }

        let processingTask = Task { @Sendable in
            do {
                for try await event in self {
                    continuation.yield(event)
                }
                timeoutTask.cancel()
                continuation.finish()
            } catch {
                timeoutTask.cancel()
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            timeoutTask.cancel()
            processingTask.cancel()
        }

        return stream
    }

    // MARK: - Side Effects

    /// Runs `action` for each event, then forwards it unchanged.
    func onEach(
        _ action: @escaping @Sendable (AgentEvent) -> Void
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                action(event)
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    /// Runs `action` with the ``AgentResult`` carried by the terminal
    /// `.lifecycle(.completed)` event, if any. Forwards all events unchanged.
    func onComplete(
        _ action: @escaping @Sendable (AgentResult) -> Void
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        onEach { event in
            if case let .lifecycle(.completed(result: result)) = event {
                action(result)
            }
        }
    }

    /// Runs `action` with the ``AgentError`` carried by a
    /// `.lifecycle(.failed)` event, if any. Forwards all events unchanged.
    func onError(
        _ action: @escaping @Sendable (AgentError) -> Void
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        onEach { event in
            if case let .lifecycle(.failed(error: error)) = event {
                action(error)
            }
        }
    }

    // MARK: - Error Handling

    /// Catches a thrown error and yields the result of `handler(error)` as a
    /// final event before completing normally. Does not re-throw.
    func catchErrors(
        _ handler: @escaping @Sendable (Error) -> AgentEvent
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation): (AsyncThrowingStream<AgentEvent, Error>, AsyncThrowingStream<AgentEvent, Error>.Continuation) = StreamHelper.makeStream()

        let task = Task { @Sendable in
            do {
                for try await event in self {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.yield(handler(error))
                continuation.finish()
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return stream
    }

    // MARK: - Debounce

    /// Collapses rapid events within `duration` into the most recent one.
    /// Useful when an upstream agent emits updates faster than a consumer
    /// (e.g. UI) can render.
    func debounce(for duration: Duration) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var lastEvent: AgentEvent?
            var lastTime: ContinuousClock.Instant?
            let durationSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

            for try await event in self {
                let now = ContinuousClock.now

                if let last = lastTime {
                    let elapsed = now - last
                    let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

                    if elapsedSeconds >= durationSeconds {
                        if let pending = lastEvent {
                            continuation.yield(pending)
                        }
                        lastEvent = event
                    } else {
                        lastEvent = event
                    }
                } else {
                    lastEvent = event
                }

                lastTime = now
            }

            // Yield final event
            if let final = lastEvent {
                continuation.yield(final)
            }
            continuation.finish()
        }
    }

    // MARK: - Throttle

    /// Emits at most one event per `interval`. The first event is always
    /// emitted; subsequent events arriving inside the window are dropped.
    func throttle(for interval: Duration) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var lastEmitTime: ContinuousClock.Instant?
            let intervalSeconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18

            for try await event in self {
                let now = ContinuousClock.now

                if let lastTime = lastEmitTime {
                    let elapsed = now - lastTime
                    let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

                    if elapsedSeconds >= intervalSeconds {
                        continuation.yield(event)
                        lastEmitTime = now
                    }
                    // Events within the interval are dropped
                } else {
                    // First event is always emitted
                    continuation.yield(event)
                    lastEmitTime = now
                }
            }
            continuation.finish()
        }
    }

    // MARK: - Buffer

    /// Collects events into arrays of size `count`, yielding each full
    /// batch. Any leftover events are yielded as a final smaller batch when
    /// the stream completes.
    func buffer(count: Int) -> AsyncThrowingStream<[AgentEvent], Error> {
        StreamHelper.makeTrackedStream { continuation in
            var buffer: [AgentEvent] = []
            buffer.reserveCapacity(count)

            for try await event in self {
                buffer.append(event)
                if buffer.count >= count {
                    continuation.yield(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }

            // Yield any remaining events
            if !buffer.isEmpty {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }

    // MARK: - CompactMap

    /// `map` + `filter` in one: yields each non-`nil` result of `transform`.
    func compactMap<T: Sendable>(
        _ transform: @escaping @Sendable (AgentEvent) async throws -> T?
    ) -> AsyncThrowingStream<T, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for try await event in self {
                if let transformed = try await transform(event) {
                    continuation.yield(transformed)
                }
            }
            continuation.finish()
        }
    }

    // MARK: - DistinctUntilChanged

    /// Drops each event that compares equal to its immediate predecessor.
    /// Equality uses ``AgentEvent``'s own `isEqual(to:)`.
    func distinctUntilChanged() -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var previousEvent: AgentEvent?

            for try await event in self {
                if let previous = previousEvent {
                    if !event.isEqual(to: previous) {
                        continuation.yield(event)
                        previousEvent = event
                    }
                } else {
                    continuation.yield(event)
                    previousEvent = event
                }
            }
            continuation.finish()
        }
    }

    // MARK: - Scan

    /// Like ``reduce(_:_:)`` but emits every intermediate accumulator value
    /// instead of only the final one.
    func scan<T: Sendable>(
        _ initial: T,
        _ combine: @escaping @Sendable (T, AgentEvent) async throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        StreamHelper.makeTrackedStream { continuation in
            var accumulator = initial

            for try await event in self {
                accumulator = try await combine(accumulator, event)
                continuation.yield(accumulator)
            }
            continuation.finish()
        }
    }
}

// MARK: - MergeErrorStrategy

/// How ``AgentEventStream/merge(_:errorStrategy:)`` handles an error from one
/// of the merged streams.
public enum MergeErrorStrategy: Sendable {
    /// Abort the merged stream immediately, propagating the first error.
    case failFast

    /// Convert the error into a `.lifecycle(.failed)` event and continue
    /// consuming the other streams. Default behavior.
    case continueAndCollect

    /// Silently drop errors. Use sparingly — information is lost.
    case ignoreErrors
}

// MARK: - AgentEventStream

/// Namespace for stream constructors and combinators. Members are used both
/// in production (``merge(_:errorStrategy:)``) and in tests
/// (``empty()`` / ``just(_:)`` / ``from(_:)`` / ``fail(_:)``).
public enum AgentEventStream {
    // MARK: Public

    /// Interleaves events from every stream as they arrive.
    /// - Parameters:
    ///   - streams: two or more ``AgentEvent`` streams
    ///   - errorStrategy: per-stream error behavior. Default: ``MergeErrorStrategy/continueAndCollect``
    public static func merge(
        _ streams: AsyncThrowingStream<AgentEvent, Error>...,
        errorStrategy: MergeErrorStrategy = .continueAndCollect
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation): (AsyncThrowingStream<AgentEvent, Error>, AsyncThrowingStream<AgentEvent, Error>.Continuation) = StreamHelper.makeStream()
        let coordinator = MergeCoordinator(continuation: continuation)

        let task = Task { @Sendable in
            await withTaskGroup(of: Void.self) { group in
                for stream in streams {
                    group.addTask {
                        do {
                            for try await event in stream {
                                await coordinator.yield(event)
                            }
                        } catch {
                            switch errorStrategy {
                            case .failFast:
                                await coordinator.finish(throwing: error)
                            case .continueAndCollect:
                                // Convert error to a failed event
                                let agentError = error as? AgentError ?? .internalError(reason: error.localizedDescription)
                                await coordinator.yield(.lifecycle(.failed(error: agentError)))
                            case .ignoreErrors:
                                // Silently ignore - legacy behavior
                                break
                            }
                        }
                    }
                }
            }
            await coordinator.finish()
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return stream
    }

    /// A stream that completes immediately with no events.
    public static func empty() -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    /// A stream that emits every element of `events` in order, then completes.
    public static func from(_ events: [AgentEvent]) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    /// A stream that emits `event` once and completes.
    public static func just(_ event: AgentEvent) -> AsyncThrowingStream<AgentEvent, Error> {
        from([event])
    }

    /// A stream that fails immediately with `error` and emits nothing.
    public static func fail(_ error: Error) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }

    // MARK: Private

    /// Actor that serializes concurrent yield/finish calls to prevent race conditions
    private actor MergeCoordinator {
        // MARK: Internal

        init(continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) {
            self.continuation = continuation
        }

        func yield(_ event: AgentEvent) {
            guard !hasFinished else { return }
            continuation.yield(event)
        }

        func finish(throwing error: Error? = nil) {
            guard !hasFinished else { return }
            hasFinished = true
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }

        // MARK: Private

        private var hasFinished = false
        private let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    }
}
