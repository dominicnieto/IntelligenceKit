// GuardrailSpecTests.swift
// Swarm V3 Tests

import Testing
@testable import Swarm

@Suite("GuardrailSpec")
struct GuardrailSpecTests {
    @Test func maxInputBlocksLongInput() async throws {
        let g = GuardrailSpec.maxInput(characters: 10)
        #expect(try await g.validateInput("hi") == nil)
        #expect(try await g.validateInput("this is way too long for ten chars") != nil)
    }

    @Test func inputNotEmptyBlocksEmpty() async throws {
        let g = GuardrailSpec.inputNotEmpty
        #expect(try await g.validateInput("") != nil)
        #expect(try await g.validateInput("hello") == nil)
    }

    @Test func customInputGuardrail() async throws {
        let g = GuardrailSpec.inputCustom(name: "no-sql") { input in
            input.lowercased().contains("drop table") ? "SQL injection detected" : nil
        }
        #expect(try await g.validateInput("DROP TABLE users") != nil)
        #expect(try await g.validateInput("hello") == nil)
    }

    @Test func maxOutputBlocksLongOutput() async throws {
        let g = GuardrailSpec.maxOutput(characters: 5)
        #expect(try await g.validateOutput("hi") == nil)
        #expect(try await g.validateOutput("this is too long") != nil)
    }

    @Test func outputCustomGuardrail() async throws {
        let g = GuardrailSpec.outputCustom(name: "no-pii") { output in
            output.contains("@") ? "Contains email" : nil
        }
        #expect(try await g.validateOutput("test@example.com") != nil)
        #expect(try await g.validateOutput("no email here") == nil)
    }

    @Test func inputGuardrailIgnoresOutputValidation() async throws {
        let g = GuardrailSpec.maxInput(characters: 10)
        #expect(try await g.validateOutput("any output is fine") == nil)
    }
}
