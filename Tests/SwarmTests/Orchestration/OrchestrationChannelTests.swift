// OrchestrationChannelTests.swift
// Swarm Framework
//
// TDD tests for OrchestrationChannel: typed channel-based data passing
// between orchestration steps via the channel bag pattern.

import Foundation
@testable import Swarm
import Testing

// MARK: - Test Helpers

/// A simple Codable type for testing typed channel round-trips.
private struct TestPayload: Codable, Sendable, Equatable {
    let name: String
    let score: Int
}

/// LegacyAgent that writes to a channel via context.
private struct ChannelWriterAgent: AgentRuntime {
    let tools: [any AnyJSONTool] = []
    let instructions = "Writes to channel"
    var configuration: AgentConfiguration

    let channel: OrchestrationChannel<String>
    let valueToWrite: String

    init(channel: OrchestrationChannel<String>, value: String, name: String = "writer") {
        self.channel = channel
        self.valueToWrite = value
        configuration = AgentConfiguration(name: name)
    }

    func run(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) async throws -> AgentResult {
        AgentResult(output: "\(input):\(valueToWrite)")
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)? = nil,
        hooks _: (any RunHooks)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}

// MARK: - OrchestrationChannel Tests

@Suite("OrchestrationChannel — Typed Channel Bag")
struct OrchestrationChannelTests {
    @Test("OrchestrationChannel stores and retrieves default value")
    func channelDefaultValue() {
        let channel = OrchestrationChannel<String>("greeting", default: "hello")
        #expect(channel.id == "greeting")
        #expect(channel.defaultValue() == "hello")
    }

    @Test("OrchestrationChannel with Int type preserves default")
    func channelIntDefault() {
        let channel = OrchestrationChannel<Int>("counter", default: 42)
        #expect(channel.id == "counter")
        #expect(channel.defaultValue() == 42)
    }

    @Test("OrchestrationChannel with Codable struct preserves default")
    func channelCodableDefault() {
        let channel = OrchestrationChannel<TestPayload>(
            "payload",
            default: TestPayload(name: "test", score: 100)
        )
        #expect(channel.id == "payload")
        let payload = channel.defaultValue()
        #expect(payload.name == "test")
        #expect(payload.score == 100)
    }

    @Test("ChannelBagStorage set and get round-trip")
    func channelBagStorageRoundTrip() async throws {
        let storage = ChannelBagStorage()
        let channel = OrchestrationChannel<String>("msg", default: "")

        try await storage.set(channel, "hello world")
        let value: String = try await storage.get(channel)
        #expect(value == "hello world")
    }

    @Test("ChannelBagStorage returns default when key not set")
    func channelBagStorageReturnsDefault() async throws {
        let storage = ChannelBagStorage()
        let channel = OrchestrationChannel<Int>("counter", default: 99)

        let value: Int = try await storage.get(channel)
        #expect(value == 99)
    }

    @Test("ChannelBagStorage handles multiple channels independently")
    func channelBagStorageMultipleChannels() async throws {
        let storage = ChannelBagStorage()
        let nameChannel = OrchestrationChannel<String>("name", default: "")
        let scoreChannel = OrchestrationChannel<Int>("score", default: 0)

        try await storage.set(nameChannel, "Alice")
        try await storage.set(scoreChannel, 42)

        let name: String = try await storage.get(nameChannel)
        let score: Int = try await storage.get(scoreChannel)
        #expect(name == "Alice")
        #expect(score == 42)
    }

    @Test("ChannelBagStorage overwrites existing value")
    func channelBagStorageOverwrites() async throws {
        let storage = ChannelBagStorage()
        let channel = OrchestrationChannel<String>("data", default: "")

        try await storage.set(channel, "first")
        try await storage.set(channel, "second")

        let value: String = try await storage.get(channel)
        #expect(value == "second")
    }

    @Test("ChannelBagStorage handles Codable struct")
    func channelBagStorageCodableStruct() async throws {
        let storage = ChannelBagStorage()
        let channel = OrchestrationChannel<TestPayload>(
            "payload",
            default: TestPayload(name: "", score: 0)
        )

        try await storage.set(channel, TestPayload(name: "Bob", score: 85))
        let value: TestPayload = try await storage.get(channel)
        #expect(value.name == "Bob")
        #expect(value.score == 85)
    }

    @Test("ChannelBagStorage snapshot returns all stored data")
    func channelBagStorageSnapshot() async throws {
        let storage = ChannelBagStorage()
        let ch1 = OrchestrationChannel<String>("a", default: "")
        let ch2 = OrchestrationChannel<String>("b", default: "")

        try await storage.set(ch1, "alpha")
        try await storage.set(ch2, "beta")

        let snapshot = await storage.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot["a"] != nil)
        #expect(snapshot["b"] != nil)
    }
}
