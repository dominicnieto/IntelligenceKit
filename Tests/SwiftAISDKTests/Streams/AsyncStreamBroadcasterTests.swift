import Testing
@testable import SwiftAISDK

@Suite("AsyncStreamBroadcaster")
struct AsyncStreamBroadcasterTests {
    @Test("replays elements sent before registration")
    func replaysElementsSentBeforeRegistration() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()

        for value in 0..<10 {
            await broadcaster.send(value)
        }

        let stream = await broadcaster.register()
        await broadcaster.finish()

        let values = try await collect(stream)

        #expect(values == Array(0..<10))
        #expect(await broadcaster.bufferCountForTesting == 10)
    }

    @Test("sealReplay drains buffered history")
    func sealReplayDrainsBufferedHistory() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()

        for value in 0..<10 {
            await broadcaster.send(value)
        }

        let stream = await broadcaster.register()
        #expect(await broadcaster.bufferCountForTesting == 10)

        await broadcaster.sealReplay()
        #expect(await broadcaster.bufferCountForTesting == 0)

        await broadcaster.finish()
        let values = try await collect(stream)

        #expect(values == Array(0..<10))
    }

    @Test("sealed broadcaster does not retain later elements")
    func sealedBroadcasterDoesNotRetainLaterElements() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()
        let stream = await broadcaster.register()

        await broadcaster.sealReplay()

        for value in 0..<100 {
            await broadcaster.send(value)
        }

        #expect(await broadcaster.bufferCountForTesting == 0)

        await broadcaster.finish()
        let values = try await collect(stream)

        #expect(values == Array(0..<100))
    }

    @Test("subscriber registered after seal receives only live elements")
    func subscriberRegisteredAfterSealReceivesOnlyLiveElements() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()

        for value in 0..<10 {
            await broadcaster.send(value)
        }

        await broadcaster.sealReplay()

        let stream = await broadcaster.register()

        for value in 10..<15 {
            await broadcaster.send(value)
        }

        await broadcaster.finish()
        let values = try await collect(stream)

        #expect(values == Array(10..<15))
        #expect(await broadcaster.bufferCountForTesting == 0)
    }

    @Test("finish after sealReplay still terminates subscribers")
    func finishAfterSealReplayStillTerminatesSubscribers() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()
        let stream = await broadcaster.register()

        await broadcaster.sealReplay()
        await broadcaster.send(1)
        await broadcaster.finish()

        let values = try await collect(stream)

        #expect(values == [1])
        #expect(await broadcaster.bufferCountForTesting == 0)
    }

    @Test("late registration after finish does not retain continuations")
    func lateRegistrationAfterFinishDoesNotRetainContinuations() async throws {
        let broadcaster = AsyncStreamBroadcaster<Int>()

        await broadcaster.send(1)
        await broadcaster.finish()

        let stream = await broadcaster.register()
        let values = try await collect(stream)

        #expect(values == [1])
        #expect(await broadcaster.continuationCountForTesting == 0)
    }

    private func collect(
        _ stream: AsyncThrowingStream<Int, Error>
    ) async throws -> [Int] {
        var values: [Int] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }
}
