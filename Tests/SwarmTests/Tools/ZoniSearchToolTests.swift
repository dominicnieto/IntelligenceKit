import Foundation
@testable import Swarm
import Testing

@Suite("ZoniSearchTool")
struct ZoniSearchToolTests {
    @Test("Unconfigured execution throws deterministic error")
    func unconfiguredExecutionThrows() async throws {
        let tool = ZoniSearchTool()

        await #expect(throws: ZoniSearchTool.Error.self) {
            _ = try await tool.execute()
        }
    }
}
