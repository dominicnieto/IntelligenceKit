// ToolV3Tests.swift
// Swarm V3 Tests

import Testing
@testable import Swarm

@Suite("ToolV3")
struct ToolV3Tests {
    @Test func parameterWrapperStoresDescription() {
        let p = ParameterV3<String>(wrappedValue: "hello", "The input")
        #expect(p.description == "The input")
        #expect(p.wrappedValue == "hello")
    }

    @Test func toolHasStaticMetadata() {
        struct GreetTool: ToolV3 {
            static let name = "greet"
            static let description = "Greet someone"
            @ParameterV3("Name") var userName: String = ""
            func call() async throws -> String { "Hello, \(userName)!" }
            func toAnyJSONTool() -> any AnyJSONTool { fatalError("stub") }
        }
        #expect(GreetTool.name == "greet")
        #expect(GreetTool.description == "Greet someone")
    }

    @Test func toolBuilderCollectsTools() {
        struct FakeTool: ToolV3 {
            static let name = "fake"
            static let description = "Fake"
            func call() async throws -> String { "" }
            func toAnyJSONTool() -> any AnyJSONTool { fatalError() }
        }
        @ToolBuilder var tools: [any ToolV3] { FakeTool(); FakeTool() }
        #expect(tools.count == 2)
    }

    @Test func toolBuilderSupportsConditionals() {
        struct FakeTool: ToolV3 {
            static let name = "fake"
            static let description = "Fake"
            func call() async throws -> String { "" }
            func toAnyJSONTool() -> any AnyJSONTool { fatalError() }
        }
        let include = true
        @ToolBuilder var tools: [any ToolV3] {
            FakeTool()
            if include { FakeTool() }
        }
        #expect(tools.count == 2)
    }
}
