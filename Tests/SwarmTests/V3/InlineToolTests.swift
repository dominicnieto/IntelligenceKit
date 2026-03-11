// InlineToolTests.swift
// Swarm V3 Tests

import Testing
@testable import Swarm

@Suite("InlineTool")
struct InlineToolTests {
    @Test func inlineToolExecutesClosure() async throws {
        let tool = InlineTool("reverse", "Reverse a string") { (s: String) in
            String(s.reversed())
        }
        #expect(tool.toolName == "reverse")
        let result = try await tool.execute(input: "hello")
        #expect(result == "olleh")
    }

    @Test func inlineToolBridgesToAnyJSONTool() async throws {
        let tool = InlineTool("upper", "Uppercase") { (s: String) in
            s.uppercased()
        }
        let bridge = tool.toAnyJSONTool()
        #expect(bridge.name == "upper")
        #expect(bridge.description == "Uppercase")
    }
}
