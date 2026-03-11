// TypedParallelTests.swift
// Swarm Framework
//
// Tests for TypedParallel and Transform convenience methods.

@testable import Swarm
import Foundation
import Testing

// MARK: - Test Helpers

/// LegacyAgent that returns a configurable output string.
private struct OutputAgent: AgentRuntime {
    let outputText: String
    let tools: [any AnyJSONTool] = []
    let instructions = "Output agent"
    let configuration: AgentConfiguration

    init(_ output: String, name: String = "OutputAgent") {
        self.outputText = output
        self.configuration = AgentConfiguration(name: name)
    }

    func run(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) async throws -> AgentResult {
        AgentResult(output: outputText)
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.started(input: input))
            continuation.yield(.completed(result: AgentResult(output: outputText)))
            continuation.finish()
        }
    }

    func cancel() async {}
}

/// LegacyAgent that always throws an error.
private struct ErrorAgent: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions = "Error agent"
    let configuration: AgentConfiguration = .init(name: "ErrorAgent")

    func run(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) async throws -> AgentResult {
        throw AgentError.invalidInput(reason: "deliberate failure")
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.started(input: input))
            continuation.finish(throwing: AgentError.invalidInput(reason: "deliberate failure"))
        }
    }

    func cancel() async {}
}

// MARK: - Transform Convenience Tests

@Suite("Transform Convenience Methods")
struct TransformConvenienceTests {
    @Test("prepend adds prefix to input")
    func prependAddsPrefix() async throws {
        let transform = Transform { input in
            "Hello, \(input)"
        }
        let result = try await transform.execute("World", context: makeContext())
        #expect(result.output == "Hello, World")
    }

    @Test("append adds suffix to input")
    func appendAddsSuffix() async throws {
        let transform = Transform { input in
            "\(input)!"
        }
        let result = try await transform.execute("Hello", context: makeContext())
        #expect(result.output == "Hello!")
    }

    @Test("replacing substitutes text")
    func replacingSubstitutesText() async throws {
        let transform = Transform { input in
            input.replacingOccurrences(of: "foo", with: "bar")
        }
        let result = try await transform.execute("foo baz foo", context: makeContext())
        #expect(result.output == "bar baz bar")
    }

    @Test("json round-trips Codable type")
    func jsonRoundTripsCodable() async throws {
        struct Item: Codable, Sendable {
            var name: String
            var count: Int
        }

        let input = #"{"name":"widget","count":5}"#
        let transform = Transform { input in
            var item = try JSONDecoder().decode(Item.self, from: Data(input.utf8))
            item.count += 10
            let encoded = try JSONEncoder().encode(item)
            return String(decoding: encoded, as: UTF8.self)
        }

        let result = try await transform.execute(input, context: makeContext())
        let decoded = try JSONDecoder().decode(Item.self, from: Data(result.output.utf8))
        #expect(decoded.name == "widget")
        #expect(decoded.count == 15)
    }

    @Test("json transform with invalid input throws")
    func jsonWithInvalidInputThrows() async throws {
        struct Item: Codable, Sendable {
            var name: String
        }

        let transform = Transform { input in
            _ = try JSONDecoder().decode(Item.self, from: Data(input.utf8))
            return input
        }
        await #expect(throws: Error.self) {
            try await transform.execute("not json", context: makeContext())
        }
    }

    @Test("prepend with empty string is identity")
    func prependEmptyIsIdentity() async throws {
        let transform = Transform { input in
            input
        }
        let result = try await transform.execute("unchanged", context: makeContext())
        #expect(result.output == "unchanged")
    }

    @Test("replacing with no matches returns original")
    func replacingNoMatchReturnsOriginal() async throws {
        let transform = Transform { input in
            input.replacingOccurrences(of: "xyz", with: "abc")
        }
        let result = try await transform.execute("hello world", context: makeContext())
        #expect(result.output == "hello world")
    }
}

// MARK: - TypedParallel Tests

@Suite("TypedParallel Tests")
struct TypedParallelTests {
    @Test("run with 2 agents returns tuple of results")
    func runWith2Agents() async throws {
        let a1 = OutputAgent("alpha")
        let a2 = OutputAgent("beta")

        let (r1, r2) = try await TypedParallel.run(a1, a2, input: "test")
        #expect(r1.output == "alpha")
        #expect(r2.output == "beta")
    }

    @Test("run with 3 agents returns tuple of results")
    func runWith3Agents() async throws {
        let a1 = OutputAgent("one")
        let a2 = OutputAgent("two")
        let a3 = OutputAgent("three")

        let (r1, r2, r3) = try await TypedParallel.run(a1, a2, a3, input: "test")
        #expect(r1.output == "one")
        #expect(r2.output == "two")
        #expect(r3.output == "three")
    }

    @Test("run with 4 agents returns tuple of results")
    func runWith4Agents() async throws {
        let a1 = OutputAgent("a")
        let a2 = OutputAgent("b")
        let a3 = OutputAgent("c")
        let a4 = OutputAgent("d")

        let (r1, r2, r3, r4) = try await TypedParallel.run(a1, a2, a3, a4, input: "test")
        #expect(r1.output == "a")
        #expect(r2.output == "b")
        #expect(r3.output == "c")
        #expect(r4.output == "d")
    }

    @Test("run with 5 agents returns tuple of results")
    func runWith5Agents() async throws {
        let a1 = OutputAgent("v")
        let a2 = OutputAgent("w")
        let a3 = OutputAgent("x")
        let a4 = OutputAgent("y")
        let a5 = OutputAgent("z")

        let (r1, r2, r3, r4, r5) = try await TypedParallel.run(a1, a2, a3, a4, a5, input: "test")
        #expect(r1.output == "v")
        #expect(r2.output == "w")
        #expect(r3.output == "x")
        #expect(r4.output == "y")
        #expect(r5.output == "z")
    }

    @Test("each tuple element has independent output")
    func tupleElementsAreIndependent() async throws {
        let a1 = OutputAgent("first", name: "Agent1")
        let a2 = OutputAgent("second", name: "Agent2")

        let (r1, r2) = try await TypedParallel.run(a1, a2, input: "same-input")
        #expect(r1.output != r2.output)
        #expect(r1.output == "first")
        #expect(r2.output == "second")
    }

    @Test("run propagates errors from any agent")
    func runPropagatesErrors() async throws {
        let good = OutputAgent("ok")
        let bad = ErrorAgent()

        await #expect(throws: AgentError.self) {
            try await TypedParallel.run(good, bad, input: "test")
        }
    }

    @Test("run with 3 agents propagates error from middle agent")
    func runPropagatesErrorFromMiddle() async throws {
        let a1 = OutputAgent("one")
        let bad = ErrorAgent()
        let a3 = OutputAgent("three")

        await #expect(throws: AgentError.self) {
            try await TypedParallel.run(a1, bad, a3, input: "test")
        }
    }
}

// MARK: - Private Helpers

private func makeContext() -> OrchestrationStepContext {
    OrchestrationStepContext(
        agentContext: AgentContext(input: ""),
        session: nil,
        hooks: nil,
        orchestrator: nil,
        orchestratorName: "test",
        handoffs: []
    )
}
