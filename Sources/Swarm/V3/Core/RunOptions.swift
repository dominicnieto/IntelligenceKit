// RunOptions.swift
// Swarm V3 API
//
// Slim replacement for 35-property AgentConfiguration.

import Foundation

// MARK: - RunOptions

/// Agent run configuration with presets. Replaces the 35-property `AgentConfiguration`.
public struct RunOptions: Sendable, Equatable {
    public var temperature: Double
    public var maxIterations: Int
    public var maxTokens: Int?
    public var timeout: Duration?
    public var retryLimit: Int
    public var streamingEnabled: Bool

    public init(
        temperature: Double = 0.7,
        maxIterations: Int = 10,
        maxTokens: Int? = nil,
        timeout: Duration? = nil,
        retryLimit: Int = 3,
        streamingEnabled: Bool = false
    ) {
        self.temperature = temperature
        self.maxIterations = maxIterations
        self.maxTokens = maxTokens
        self.timeout = timeout
        self.retryLimit = retryLimit
        self.streamingEnabled = streamingEnabled
    }
}

// MARK: - Presets

extension RunOptions {
    /// Balanced defaults (temperature 0.7, 10 iterations).
    public static let `default` = RunOptions()

    /// High creativity (temperature 1.2).
    public static let creative = RunOptions(temperature: 1.2)

    /// Deterministic output (temperature 0.0, 5 iterations).
    public static let precise = RunOptions(temperature: 0.0, maxIterations: 5)

    /// Quick responses (3 iterations, 512 max tokens).
    public static let fast = RunOptions(temperature: 0.7, maxIterations: 3, maxTokens: 512)
}
