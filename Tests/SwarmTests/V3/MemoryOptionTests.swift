// MemoryOptionTests.swift
// Swarm V3 Tests

import Testing
@testable import Swarm

@Suite("MemoryOption")
struct MemoryOptionTests {
    @Test func noneReturnsNil() {
        #expect(MemoryOption.none.makeMemory() == nil)
    }

    @Test func conversationCreatesMemory() {
        let mem = MemoryOption.conversation(limit: 50).makeMemory()
        #expect(mem != nil)
    }

    @Test func conversationDefaultLimit() {
        let mem = MemoryOption.conversation().makeMemory()
        #expect(mem != nil)
    }

    @Test func slidingWindowCreatesMemory() {
        let mem = MemoryOption.slidingWindow(maxTokens: 2000).makeMemory()
        #expect(mem != nil)
    }
}
