import Foundation

/**
 Splits an `AsyncThrowingStream` into two identical streams.

 Port of `ReadableStream.prototype.tee()` used in `@ai-sdk/ai`.
 */
func teeAsyncThrowingStream<Element: Sendable>(
    _ source: AsyncThrowingStream<Element, Error>
) -> (AsyncThrowingStream<Element, Error>, AsyncThrowingStream<Element, Error>) {
    let distributor = TeeDistributor<Element>(expectedConsumerCount: 2)

    let streamA = makeTeeStream(distributor: distributor)
    let streamB = makeTeeStream(distributor: distributor)

    let pumpTask = Task {
        do {
            for try await value in source {
                await distributor.broadcast(value)
            }
            await distributor.finish(error: nil)
        } catch is CancellationError {
            await distributor.finish(error: nil)
        } catch {
            await distributor.finish(error: error)
        }
    }

    Task {
        await distributor.register(task: pumpTask)
    }

    return (streamA, streamB)
}

private func makeTeeStream<Element: Sendable>(
    distributor: TeeDistributor<Element>
) -> AsyncThrowingStream<Element, Error> {
    let identifier = UUID()
    let (stream, continuation) = AsyncThrowingStream.makeStream(
        of: Element.self,
        throwing: Error.self
    )

    continuation.onTermination = { _ in
        Task {
            await distributor.removeContinuation(id: identifier)
        }
    }

    Task {
        await distributor.addContinuation(id: identifier, continuation: continuation)
    }

    return stream
}

// MARK: - Distributor

private actor TeeDistributor<Element: Sendable> {
    private let expectedConsumerCount: Int

    private var continuations: [UUID: AsyncThrowingStream<Element, Error>.Continuation] = [:]
    private var pendingValues: [Element] = []
    private var finished = false
    private var finishError: Error?
    private var pumpTask: Task<Void, Never>?

    init(expectedConsumerCount: Int) {
        self.expectedConsumerCount = expectedConsumerCount
    }

    func register(task: Task<Void, Never>) {
        pumpTask = task
    }

    func addContinuation(
        id: UUID,
        continuation: AsyncThrowingStream<Element, Error>.Continuation
    ) {
        if let error = finishError {
            continuation.finish(throwing: error)
            return
        }

        if finished {
            continuation.finish()
            return
        }

        continuations[id] = continuation

        for value in pendingValues {
            continuation.yield(value)
        }

        if continuations.count >= expectedConsumerCount {
            pendingValues.removeAll(keepingCapacity: false)
        }
    }

    func removeContinuation(id: UUID) {
        continuations[id] = nil
        let shouldTerminate = continuations.isEmpty && !finished

        if shouldTerminate {
            finish(error: nil)
        }
    }

    func broadcast(_ value: Element) {
        guard !finished else { return }

        if continuations.count < expectedConsumerCount {
            pendingValues.append(value)
        }

        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    func finish(error: Error?) {
        guard !finished else { return }

        finished = true
        finishError = error
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        pendingValues.removeAll(keepingCapacity: false)
        let task = pumpTask
        pumpTask = nil
        task?.cancel()

        for continuation in activeContinuations {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}
