import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Reads a UI message stream and yields intermediate `Message` snapshots.

 Port of `@ai-sdk/ai/src/ui-message-stream/read-ui-message-stream.ts`.
 */
public func readUIMessageStream<Message: UIMessageConvertible>(
    message: Message? = nil,
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    terminateOnError: Bool = false,
    onError: (@Sendable (Error) -> Void)? = nil
) -> AsyncIterableStream<Message> {
    let state = createStreamingUIMessageState(
        lastMessage: message,
        messageId: message?.id ?? ""
    )

    let (output, continuation) = AsyncThrowingStream.makeStream(
        of: Message.self,
        throwing: Error.self
    )
    let coordinator = ReadUIMessageStreamCoordinator(
        state: state,
        continuation: continuation,
        terminateOnError: terminateOnError,
        onError: onError
    )

    continuation.onTermination = { _ in
        Task {
            await coordinator.cancel()
        }
    }

    Task {
        await coordinator.start(stream: stream)
    }

    return createAsyncIterableStream(source: output)
}

// MARK: - Coordinator

private actor ReadUIMessageStreamCoordinator<Message: UIMessageConvertible> {
    private let state: StreamingUIMessageState<Message>
    private let continuation: AsyncThrowingStream<Message, Error>.Continuation
    private let terminateOnError: Bool
    private let errorHandler: (@Sendable (Error) -> Void)?

    private var hasErrored = false
    private var consumeTask: Task<Void, Never>?

    init(
        state: StreamingUIMessageState<Message>,
        continuation: AsyncThrowingStream<Message, Error>.Continuation,
        terminateOnError: Bool,
        onError: (@Sendable (Error) -> Void)?
    ) {
        self.state = state
        self.continuation = continuation
        self.terminateOnError = terminateOnError
        self.errorHandler = onError
    }

    func start(stream: AsyncThrowingStream<AnyUIMessageChunk, Error>) {
        let processedStream = processUIMessageStream(
            stream: stream,
            runUpdateMessageJob: { job in
                try await job(
                    StreamingUIMessageJobContext(
                        state: self.state,
                        write: { await self.emitCurrentMessage() }
                    )
                )
            },
            onError: { error in
                await self.handleError(error)
                if self.terminateOnError {
                    throw error
                }
            }
        )

        consumeTask = Task {
            do {
                for try await _ in processedStream {
                    // Drain the processed stream to keep state updates flowing.
                }
                self.finishIfNeeded()
            } catch {
                await self.handleError(error)
                self.finishIfNeeded()
            }
        }
    }

    private func emitCurrentMessage() async {
        guard !hasErrored else { return }
        continuation.yield(await state.messageSnapshot())
    }

    private func handleError(_ error: Error) async {
        errorHandler?(error)

        guard terminateOnError, !hasErrored else {
            return
        }

        hasErrored = true
        continuation.finish(throwing: error)
        cancel()
    }

    private func finishIfNeeded() {
        guard !hasErrored else { return }
        continuation.finish()
    }

    func cancel() {
        let task = consumeTask
        consumeTask = nil
        task?.cancel()
    }
}
