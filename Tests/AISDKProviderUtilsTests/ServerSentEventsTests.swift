import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("ServerSentEvents")
struct ServerSentEventsTests {
    private func makeStream(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
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
}
