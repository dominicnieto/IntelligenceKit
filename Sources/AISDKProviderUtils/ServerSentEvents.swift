import Foundation
import EventSource

package struct ServerSentEvent: Sendable, Equatable {
    package var id: String?
    package var event: String?
    package var data: String
    package var retry: Int?

    package init(id: String?, event: String?, data: String, retry: Int?) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

private struct DataChunkByteSequence: AsyncSequence, Sendable {
    typealias Element = UInt8

    let base: AsyncThrowingStream<Data, Error>

    func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {
        private var base: AsyncThrowingStream<Data, Error>.AsyncIterator
        private var chunk = Data()
        private var index: Data.Index?

        init(base: AsyncThrowingStream<Data, Error>.AsyncIterator) {
            self.base = base
        }

        mutating func next() async throws -> UInt8? {
            while true {
                if let index {
                    let byte = chunk[index]
                    let nextIndex = chunk.index(after: index)
                    if nextIndex < chunk.endIndex {
                        self.index = nextIndex
                    } else {
                        self.index = nil
                        chunk.removeAll(keepingCapacity: true)
                    }
                    return byte
                }

                guard let nextChunk = try await base.next() else {
                    return nil
                }

                guard !nextChunk.isEmpty else {
                    continue
                }

                chunk = nextChunk
                index = chunk.startIndex
            }
        }
    }
}

package func makeServerSentEventStream(
    from input: AsyncThrowingStream<Data, Error>
) -> AsyncThrowingStream<ServerSentEvent, Error> {
    let bytes = DataChunkByteSequence(base: input)

    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await event in bytes.events {
                    continuation.yield(
                        ServerSentEvent(
                            id: event.id,
                            event: event.event,
                            data: event.data,
                            retry: event.retry
                        )
                    )
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
