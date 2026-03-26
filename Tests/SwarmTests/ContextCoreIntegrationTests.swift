import Testing

@testable import Swarm

@Suite("ContextCore Integration")
struct ContextCoreIntegrationTests {
    @Test("ContextCoreMemory can ingest messages and build a context window")
    func contextCoreMemoryBuildWindow() async throws {
        let memory = try ContextCoreMemory(
            configuration: ContextCoreMemoryConfiguration(
                promptTitle: "ContextCore Test Memory",
                promptGuidance: "Test guidance"
            )
        )

        await memory.beginMemorySession()
        await memory.add(.user("alpha"))
        await memory.add(.assistant("beta"))

        let context = await memory.context(for: "alpha", tokenLimit: 256)

        #expect(await memory.count == 2)
        #expect(await memory.isEmpty == false)
        #expect(context.contains("alpha"))
        #expect(context.contains("beta"))
    }
}
