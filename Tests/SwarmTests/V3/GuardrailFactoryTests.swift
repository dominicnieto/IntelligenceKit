// GuardrailFactoryTests.swift
// SwarmTests
//
// TDD tests for V3 guardrail static factories on InputGuard/OutputGuard.
// These tests verify the new factory API and that ClosureInputGuardrail/ClosureOutputGuardrail
// are no longer part of the public API surface.

import Foundation
@testable import Swarm
import Testing

// MARK: - InputGuard Factory Tests

@Suite("InputGuard Factory Methods")
struct InputGuardFactoryTests {

    // MARK: - maxLength Factory

    @Test("InputGuard.maxLength passes input within limit")
    func maxLengthPasses() async throws {
        let g = InputGuard.maxLength(500)
        let result = try await g.validate("hello", context: nil)
        #expect(!result.tripwireTriggered)
    }

    @Test("InputGuard.maxLength blocks input exceeding limit")
    func maxLengthBlocks() async throws {
        let g = InputGuard.maxLength(5)
        let result = try await g.validate("hello world", context: nil)
        #expect(result.tripwireTriggered)
        #expect(result.message?.contains("exceeds maximum length") == true)
    }

    @Test("InputGuard.maxLength has correct default name")
    func maxLengthDefaultName() {
        let g = InputGuard.maxLength(100)
        #expect(g.name == "MaxLengthGuardrail")
    }

    @Test("InputGuard.maxLength accepts custom name")
    func maxLengthCustomName() {
        let g = InputGuard.maxLength(100, name: "MyLengthCheck")
        #expect(g.name == "MyLengthCheck")
    }

    @Test("InputGuard.maxLength includes metadata on tripwire")
    func maxLengthMetadata() async throws {
        let g = InputGuard.maxLength(3)
        let result = try await g.validate("toolong", context: nil)
        #expect(result.tripwireTriggered)
        #expect(result.metadata["length"]?.intValue == 7)
        #expect(result.metadata["limit"]?.intValue == 3)
    }

    // MARK: - notEmpty Factory

    @Test("InputGuard.notEmpty passes non-empty input")
    func notEmptyPasses() async throws {
        let g = InputGuard.notEmpty()
        let result = try await g.validate("hello", context: nil)
        #expect(!result.tripwireTriggered)
    }

    @Test("InputGuard.notEmpty blocks empty input")
    func notEmptyBlocksEmpty() async throws {
        let g = InputGuard.notEmpty()
        let result = try await g.validate("", context: nil)
        #expect(result.tripwireTriggered)
        #expect(result.message?.contains("empty") == true)
    }

    @Test("InputGuard.notEmpty blocks whitespace-only input")
    func notEmptyBlocksWhitespace() async throws {
        let g = InputGuard.notEmpty()
        let result = try await g.validate("   \n\t  ", context: nil)
        #expect(result.tripwireTriggered)
    }

    @Test("InputGuard.notEmpty has correct default name")
    func notEmptyDefaultName() {
        let g = InputGuard.notEmpty()
        #expect(g.name == "NotEmptyGuardrail")
    }

    @Test("InputGuard.notEmpty accepts custom name")
    func notEmptyCustomName() {
        let g = InputGuard.notEmpty(name: "RequiredInput")
        #expect(g.name == "RequiredInput")
    }

    // MARK: - custom Factory

    @Test("InputGuard.custom creates guardrail with closure")
    func customFactory() async throws {
        let g = InputGuard.custom("no_numbers") { input in
            input.rangeOfCharacter(from: .decimalDigits) == nil
                ? .passed()
                : .tripwire(message: "Numbers not allowed")
        }
        let passResult = try await g.validate("hello", context: nil)
        #expect(!passResult.tripwireTriggered)

        let failResult = try await g.validate("hello123", context: nil)
        #expect(failResult.tripwireTriggered)
    }

    // MARK: - Protocol-level dot-syntax usage

    @Test("Factory guardrails work in [any InputGuardrail] arrays")
    func factoryInArray() async throws {
        let guardrails: [any InputGuardrail] = [
            InputGuard.maxLength(1000),
            InputGuard.notEmpty(),
        ]
        #expect(guardrails.count == 2)

        for g in guardrails {
            let result = try await g.validate("valid input", context: nil)
            #expect(!result.tripwireTriggered)
        }
    }
}

// MARK: - OutputGuard Factory Tests

@Suite("OutputGuard Factory Methods")
struct OutputGuardFactoryTests {

    // MARK: - maxLength Factory

    @Test("OutputGuard.maxLength passes output within limit")
    func maxLengthPasses() async throws {
        let g = OutputGuard.maxLength(500)
        let result = try await g.validate("short", agent: MockOutputAgent(), context: nil)
        #expect(!result.tripwireTriggered)
    }

    @Test("OutputGuard.maxLength blocks output exceeding limit")
    func maxLengthBlocks() async throws {
        let g = OutputGuard.maxLength(5)
        let result = try await g.validate("way too long output", agent: MockOutputAgent(), context: nil)
        #expect(result.tripwireTriggered)
        #expect(result.message?.contains("exceeds maximum length") == true)
    }

    @Test("OutputGuard.maxLength has correct default name")
    func maxLengthDefaultName() {
        let g = OutputGuard.maxLength(100)
        #expect(g.name == "MaxOutputLengthGuardrail")
    }

    @Test("OutputGuard.maxLength accepts custom name")
    func maxLengthCustomName() {
        let g = OutputGuard.maxLength(100, name: "MyOutputCheck")
        #expect(g.name == "MyOutputCheck")
    }

    @Test("OutputGuard.maxLength includes metadata on tripwire")
    func maxLengthMetadata() async throws {
        let g = OutputGuard.maxLength(3)
        let result = try await g.validate("toolong", agent: MockOutputAgent(), context: nil)
        #expect(result.tripwireTriggered)
        #expect(result.metadata["length"]?.intValue == 7)
        #expect(result.metadata["limit"]?.intValue == 3)
    }

    // MARK: - custom Factory

    @Test("OutputGuard.custom creates guardrail with closure")
    func customFactory() async throws {
        let g = OutputGuard.custom("no_pii") { output in
            output.contains("SSN") ? .tripwire(message: "PII detected") : .passed()
        }
        let passResult = try await g.validate("safe output", agent: MockOutputAgent(), context: nil)
        #expect(!passResult.tripwireTriggered)

        let failResult = try await g.validate("SSN: 123-45-6789", agent: MockOutputAgent(), context: nil)
        #expect(failResult.tripwireTriggered)
    }

    // MARK: - Protocol-level dot-syntax usage

    @Test("Factory guardrails work in [any OutputGuardrail] arrays")
    func factoryInArray() async throws {
        let guardrails: [any OutputGuardrail] = [
            OutputGuard.maxLength(1000),
        ]
        #expect(guardrails.count == 1)

        let agent = MockOutputAgent()
        for g in guardrails {
            let result = try await g.validate("valid output", agent: agent, context: nil)
            #expect(!result.tripwireTriggered)
        }
    }
}

// MARK: - Mock for OutputGuardrail tests

private struct MockOutputAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String = "Mock"
    nonisolated let configuration: AgentConfiguration = .default
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil

    func run(_: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) async throws -> AgentResult {
        AgentResult(output: "mock", toolCalls: [], toolResults: [], iterationCount: 1)
    }

    nonisolated func stream(_ input: String, session _: (any Session)? = nil, observer _: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}
