import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates a UI message stream by wiring an execution closure to a writer.

 Port of `@ai-sdk/ai/src/ui-message-stream/create-ui-message-stream.ts`.
 */
public func createUIMessageStream<Message: UIMessageConvertible>(
    execute: @escaping @Sendable (_ writer: DefaultUIMessageStreamWriter<Message>) async throws -> Void,
    onError mapError: @escaping @Sendable (Error) -> String = { AISDKProvider.getErrorMessage($0) },
    originalMessages: [Message]? = nil,
    onStepFinish: UIMessageStreamOnStepFinishCallback<Message>? = nil,
    onFinish: UIMessageStreamOnFinishCallback<Message>? = nil,
    generateId: @escaping IDGenerator = generateID
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    let (rawStream, continuation) = AsyncThrowingStream.makeStream(
        of: AnyUIMessageChunk.self,
        throwing: Error.self
    )
    let state = UIMessageStreamCoordinator(
        continuation: continuation,
        errorMapper: mapError
    )
    continuation.onTermination = { termination in
        Task {
            await state.handleTermination(termination)
        }
    }
    let writer = DefaultUIMessageStreamWriter<Message>(state: state, errorMapper: mapError)

    // Tie the execution task lifetime to the resulting stream to avoid leaked tasks
    // when consumers cancel early. This mirrors the upstream behavior where
    // the web stream controller owns the producer.
    let executeTask = Task {
        do {
            try await execute(writer)
        } catch {
            await state.emitError(error)
        }
        await state.requestFinish()
    }

    let finishHandler: ErrorHandler = { error in
        _ = mapError(error)
    }

    let handledStream = handleUIMessageStreamFinish(
        stream: rawStream,
        messageId: generateId(),
        originalMessages: originalMessages ?? [],
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onError: finishHandler
    )

    // Wrap and forward handledStream while ensuring executeTask is cancelled on termination.
    return AsyncThrowingStream { continuation in
        let forwardTask = Task {
            do {
                for try await chunk in handledStream {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            executeTask.cancel()
            forwardTask.cancel()
        }
    }
}

// MARK: - Writer

/**
 Default writer implementation exposed to the execution closure.
 */
public struct DefaultUIMessageStreamWriter<MessageType: UIMessageConvertible>: UIMessageStreamWriter {
    public typealias Message = MessageType

    private let state: UIMessageStreamCoordinator
    private let errorMapper: @Sendable (Error) -> String

    init(
        state: UIMessageStreamCoordinator,
        errorMapper: @escaping @Sendable (Error) -> String
    ) {
        self.state = state
        self.errorMapper = errorMapper
    }

    public func write(_ part: AnyUIMessageChunk) async {
        await state.emit(part)
    }

    public func merge(_ stream: AsyncIterableStream<AnyUIMessageChunk>) async {
        await state.merge(stream: stream, errorMapper: errorMapper)
    }

    public var onError: ErrorHandler? {
        { error in
            _ = errorMapper(error)
        }
    }
}

// MARK: - Internal State

actor UIMessageStreamCoordinator {
    private let continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation
    private var isFinished = false
    private var finishRequested = false
    private var activeMergeCount = 0
    private var mergeTasks: [UUID: Task<Void, Never>] = [:]
    private let errorMapper: @Sendable (Error) -> String

    init(
        continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation,
        errorMapper: @escaping @Sendable (Error) -> String
    ) {
        self.continuation = continuation
        self.errorMapper = errorMapper
    }

    func emit(_ chunk: AnyUIMessageChunk) {
        guard !isFinished else { return }
        continuation.yield(chunk)
    }

    func emitError(_ error: Error) {
        emit(.error(errorText: errorMapper(error)))
    }

    func merge(
        stream: AsyncIterableStream<AnyUIMessageChunk>,
        errorMapper: @escaping @Sendable (Error) -> String
    ) {
        guard !isFinished else { return }

        let identifier = UUID()
        activeMergeCount += 1
        let task = Task {
            defer {
                Task {
                    self.mergeFinished(id: identifier)
                }
            }

            var iterator = stream.makeAsyncIterator()
            do {
                while let value = try await iterator.next() {
                    self.emit(value)
                }
            } catch is CancellationError {
                // Cancellation propagates silently.
            } catch {
                self.emit(.error(errorText: errorMapper(error)))
            }
        }

        mergeTasks[identifier] = task
    }

    func requestFinish() {
        finishRequested = true
        if !isFinished && activeMergeCount == 0 {
            finish()
        }
    }

    private func mergeFinished(id: UUID) {
        let task = mergeTasks.removeValue(forKey: id)
        task?.cancel()
        if activeMergeCount > 0 {
            activeMergeCount -= 1
        }
        if finishRequested && !isFinished && activeMergeCount == 0 {
            finish()
        }
    }

    func handleTermination(
        _ termination: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation.Termination
    ) {
        switch termination {
        case .finished:
            finish()
        case .cancelled:
            cancelMerges()
            finish()
        @unknown default:
            finish()
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        continuation.finish()
        cancelMerges()
    }

    private func cancelMerges() {
        let tasks = Array(mergeTasks.values)
        mergeTasks.removeAll()
        activeMergeCount = 0
        for task in tasks {
            task.cancel()
        }
    }
}
