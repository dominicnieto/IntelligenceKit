import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("ServerSentEvents")
struct ServerSentEventsTests {
    private actor BoolProbe {
        private var value = false

        func setTrue() {
            value = true
        }

        func get() -> Bool {
            value
        }
    }

    private func makeStream(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func eventually(
        timeout: TimeInterval = 1.0,
        intervalNanoseconds: UInt64 = 10_000_000,
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        return await predicate()
    }

    @Test("parses fragmented multibyte UTF-8 across chunk boundaries")
    func parsesFragmentedMultibyteUTF8() async throws {
        let event = "data: {\"text\":\"The café serves résumés\"}\n\n"
        let bytes = Data(event.utf8)
        let splitToken = Data([0xC3, 0xA9])
        let range = try #require(bytes.firstRange(of: splitToken))
        let splitIndex = range.lowerBound + 1

        let stream = makeStream([
            Data(bytes.prefix(splitIndex)),
            Data(bytes.suffix(from: splitIndex))
        ])

        var events: [ServerSentEvent] = []
        for try await event in makeServerSentEventStream(from: stream) {
            events.append(event)
        }

        #expect(events.count == 1)
        #expect(events[0].data == "{\"text\":\"The café serves résumés\"}")
    }

    @Test("assembles multiline SSE data")
    func assemblesMultilineData() async throws {
        let stream = makeStream([
            Data("data: line1\n".utf8),
            Data("data: line2\n\n".utf8)
        ])

        var events: [ServerSentEvent] = []
        for try await event in makeServerSentEventStream(from: stream) {
            events.append(event)
        }

        #expect(events.count == 1)
        #expect(events[0].data == "line1\nline2")
    }

    @Test("cancels upstream when the consumer stops early")
    func cancelsUpstreamWhenConsumerStopsEarly() async throws {
        let terminationProbe = BoolProbe()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("data: hello\n\n".utf8))
            continuation.onTermination = { _ in
                Task {
                    await terminationProbe.setTrue()
                }
            }
        }

        let events = makeServerSentEventStream(from: stream)
        let consumer = Task {
            for try await _ in events {
                // Keep waiting for more input until the task is cancelled.
            }
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        consumer.cancel()
        _ = await consumer.result

        let upstreamCancelled = await eventually {
            await terminationProbe.get()
        }
        #expect(upstreamCancelled)
    }
}
