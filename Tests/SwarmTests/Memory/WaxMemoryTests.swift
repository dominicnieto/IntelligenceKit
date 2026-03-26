import Foundation
@testable import Swarm
import Testing

@Suite("WaxMemory Tests")
struct WaxMemoryTests {
    @Test("clear resets persisted retrieval state and visibility methods")
    func clearResetsPersistedStateAndVisibility() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let memory = try await WaxMemory(url: url)
        let content = "waxclear\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        await memory.add(.user(content))

        let beforeContext = await memory.context(for: content, tokenLimit: 4_000)
        #expect(beforeContext.contains(content))
        #expect(await memory.count == 1)
        #expect(await !memory.isEmpty)
        #expect((await memory.allMessages()).count == 1)

        await memory.clear()

        #expect(await memory.count == 0)
        #expect(await memory.isEmpty)
        #expect((await memory.allMessages()).isEmpty)
        let afterContext = await memory.context(for: content, tokenLimit: 4_000)
        #expect(afterContext.isEmpty)
    }

    @Test("clear removes old retrieval results before new writes")
    func clearRemovesOldRetrievalResultsBeforeNewWrites() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let memory = try await WaxMemory(url: url)
        let first = "waxfirst\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let second = "waxsecond\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        await memory.add(.user(first))
        await memory.clear()
        await memory.add(.assistant(second))

        let firstContext = await memory.context(for: first, tokenLimit: 4_000)
        let secondContext = await memory.context(for: second, tokenLimit: 4_000)

        #expect(!secondContext.isEmpty)
        #expect(secondContext.contains(second))
        #expect(!firstContext.contains(first))
        #expect(await memory.count == 1)
        #expect((await memory.allMessages()).count == 1)
    }

    @Test("add is idempotent for repeated message IDs")
    func addIsIdempotentForRepeatedMessageIDs() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let message = MemoryMessage(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            role: .user,
            content: "wax-idempotent",
            timestamp: Date(timeIntervalSince1970: 5)
        )

        do {
            let memory = try await WaxMemory(url: url)
            await memory.add(message)
            await memory.add(message)

            #expect(await memory.count == 1)
            #expect(await !memory.isEmpty)
            #expect((await memory.allMessages()).map(\.id) == [message.id])
        }

        let reopened = try await WaxMemory(url: url)
        #expect(await reopened.count == 1)
        #expect((await reopened.allMessages()).map(\.id) == [message.id])
    }
}

private func makeTemporaryWaxURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swarm-wax-memory-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("wax-memory-\(UUID().uuidString).mv2s")
}
