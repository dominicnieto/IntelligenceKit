// RunOptionsTests.swift
// Swarm V3 Tests

import Testing
@testable import Swarm

@Suite("RunOptions")
struct RunOptionsTests {
    @Test func defaultPreset() {
        let o = RunOptions.default
        #expect(o.temperature == 0.7)
        #expect(o.maxIterations == 10)
        #expect(o.maxTokens == nil)
        #expect(o.timeout == nil)
        #expect(o.retryLimit == 3)
        #expect(o.streamingEnabled == false)
    }

    @Test func precisePreset() {
        let p = RunOptions.precise
        #expect(p.temperature == 0.0)
        #expect(p.maxIterations == 5)
    }

    @Test func creativePreset() {
        #expect(RunOptions.creative.temperature == 1.2)
    }

    @Test func fastPreset() {
        let f = RunOptions.fast
        #expect(f.maxIterations == 3)
        #expect(f.maxTokens == 512)
    }

    @Test func customInit() {
        let o = RunOptions(temperature: 0.5, maxIterations: 3)
        #expect(o.temperature == 0.5)
        #expect(o.maxIterations == 3)
    }

    @Test func equatable() {
        #expect(RunOptions.default == RunOptions.default)
        #expect(RunOptions.default != RunOptions.precise)
    }
}
