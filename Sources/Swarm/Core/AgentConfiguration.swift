// AgentConfiguration.swift
// Swarm Framework
//
// Runtime configuration settings for agent execution.

import Foundation
import Logging

/// How the agent sizes the prompt context envelope.
public enum ContextMode: Sendable, Equatable {
    /// Adaptive sizing based on the configured ``ContextProfile`` / platform.
    case adaptive

    /// Hard 4K token limit. Overrides the configured profile.
    case strict4k
}

/// Optional graph runtime override for orchestration execution.
struct SwarmGraphRunOptionsOverride: Sendable, Equatable {
    var maxSteps: Int?
    var maxConcurrentTasks: Int?
    var debugPayloads: Bool?
    var deterministicTokenStreaming: Bool?
    var eventBufferCapacity: Int?

    init(
        maxSteps: Int? = nil,
        maxConcurrentTasks: Int? = nil,
        debugPayloads: Bool? = nil,
        deterministicTokenStreaming: Bool? = nil,
        eventBufferCapacity: Int? = nil
    ) {
        self.maxSteps = maxSteps
        self.maxConcurrentTasks = maxConcurrentTasks
        self.debugPayloads = debugPayloads
        self.deterministicTokenStreaming = deterministicTokenStreaming
        self.eventBufferCapacity = eventBufferCapacity
    }
}

// MARK: - InferencePolicy

/// Routing hints for inference provider selection when multiple backends are
/// available. Forwarded to the graph runtime's routing layer.
public struct InferencePolicy: Sendable, Equatable {
    public enum LatencyTier: String, Sendable, Equatable {
        /// Low-latency, interactive use (e.g. chat).
        case interactive
        /// Higher latency acceptable (e.g. batch processing).
        case background
    }

    public enum NetworkState: String, Sendable, Equatable {
        case offline
        case online
        case metered
    }

    public var latencyTier: LatencyTier

    /// When `true`, force on-device/private inference.
    public var privacyRequired: Bool

    /// Optional output-token budget hint. Caps generation length, **not** the
    /// context window — for context sizing use ``AgentConfiguration/contextProfile``.
    public var tokenBudget: Int?

    public var networkState: NetworkState

    public init(
        latencyTier: LatencyTier = .interactive,
        privacyRequired: Bool = false,
        tokenBudget: Int? = nil,
        networkState: NetworkState = .online
    ) {
        if let tokenBudget, tokenBudget <= 0 {
            Log.agents.warning("InferencePolicy: tokenBudget \(tokenBudget) must be > 0; dropping value")
        }
        self.latencyTier = latencyTier
        self.privacyRequired = privacyRequired
        self.tokenBudget = tokenBudget.flatMap { $0 > 0 ? $0 : nil }
        self.networkState = networkState
    }
}

// MARK: - AgentConfiguration

/// Runtime configuration for an ``Agent`` — iteration limits, timeouts, model
/// parameters, streaming/tool behavior, session history bounds, and tracing.
///
/// Use ``default`` and chain builder modifiers:
///
/// ```swift
/// let config = AgentConfiguration.default
///     .name("WeatherBot")
///     .maxIterations(20)
///     .temperature(0.8)
///     .timeout(.seconds(120))
/// ```
///
/// Value type, `Sendable`, safe across concurrency boundaries.
public struct AgentConfiguration: Sendable, Equatable {
    // MARK: - Defaults

    /// Sensible defaults for typical agent use.
    public static let `default` = AgentConfiguration()

    /// Defaults tuned for on-device inference (tighter session history, strict
    /// context envelope on non-macOS platforms).
    public static var onDeviceDefault: AgentConfiguration {
        #if os(macOS)
        AgentConfiguration(
            contextProfile: .platformDefault,
            sessionHistoryLimit: 24
        )
        #else
        AgentConfiguration(
            sessionHistoryLimit: 12,
            contextMode: .strict4k
        )
        #endif
    }

    // MARK: - Identity

    /// Display name used in logs, tracing, and handoff identification. Default: `"Agent"`
    public var name: String

    // MARK: - Iteration Limits

    /// Maximum reasoning iterations before throwing ``AgentError/maxIterationsExceeded(iterations:)``.
    /// Default: `10`
    public var maxIterations: Int

    /// Maximum total execution time. Default: `60` seconds.
    public var timeout: Duration

    // MARK: - Model Settings

    /// Model sampling temperature in `0.0 ... 2.0`. Default: `1.0`
    public var temperature: Double

    /// Maximum tokens to generate per response. `nil` uses the provider default.
    public var maxTokens: Int?

    /// Sequences that stop generation when encountered. Default: `[]`
    public var stopSequences: [String]

    /// Advanced model settings. When set, takes precedence over ``temperature``,
    /// ``maxTokens``, and ``stopSequences``.
    public var modelSettings: ModelSettings?

    // MARK: - Context Settings

    /// Context budgeting profile. Default: ``ContextProfile/platformDefault``
    public var contextProfile: ContextProfile

    /// Context envelope mode. ``ContextMode/strict4k`` overrides the profile's
    /// sizing with a hard 4K limit. Default: ``ContextMode/adaptive``
    public var contextMode: ContextMode

    // MARK: - Graph Runtime Settings

    /// Internal graph-runtime override. Not public API; may change without notice.
    var graphRunOptionsOverride: SwarmGraphRunOptionsOverride?

    /// Routing hints consumed by the graph runtime when picking a provider.
    public var inferencePolicy: InferencePolicy?

    // MARK: - Behavior Settings

    /// Stream incremental ``AgentEvent`` chunks. When `false`, return a single
    /// completion event. Default: `true`
    public var enableStreaming: Bool

    /// Include detailed tool-call records in ``AgentResponse``. Default: `true`
    public var includeToolCallDetails: Bool

    /// Stop execution on the first tool-call error instead of surfacing it in
    /// the result and continuing. Default: `false`
    public var stopOnToolError: Bool

    /// Emit reasoning events (model chain-of-thought when the provider exposes it).
    /// Default: `true`
    public var includeReasoning: Bool

    // MARK: - Session Settings

    /// Maximum recent session messages to replay as context on each run.
    /// `nil` loads everything (expensive on long sessions). Default: `50`
    public var sessionHistoryLimit: Int?

    // MARK: - Parallel Execution Settings

    /// Execute multiple tool calls from a single turn concurrently. Requires
    /// tools to be independent and thread-safe. Default: `false`
    public var parallelToolCalls: Bool

    // MARK: - Response Tracking Settings

    /// Response ID to resume a conversation from. Usually set automatically
    /// when ``autoPreviousResponseId`` is enabled.
    public var previousResponseId: String?

    /// Automatically carry the previous response ID forward across
    /// `run()` calls on the same agent instance. Default: `false`
    public var autoPreviousResponseId: Bool

    // MARK: - Observability Settings

    /// When no explicit tracer is configured, use a debug-level `SwiftLogTracer`.
    /// Default: `true`
    public var defaultTracingEnabled: Bool

    // MARK: - Initialization

    /// Creates a configuration. All parameters have sensible defaults — see the
    /// individual property docs for specifics. Invalid values (non-positive
    /// `maxIterations` or `timeout`, out-of-range `temperature`) are clamped
    /// with a warning rather than rejected.
    public init(
        name: String = "Agent",
        maxIterations: Int = 10,
        timeout: Duration = .seconds(60),
        temperature: Double = 1.0,
        maxTokens: Int? = nil,
        stopSequences: [String] = [],
        modelSettings: ModelSettings? = nil,
        contextProfile: ContextProfile = .platformDefault,
        inferencePolicy: InferencePolicy? = nil,
        enableStreaming: Bool = true,
        includeToolCallDetails: Bool = true,
        stopOnToolError: Bool = false,
        includeReasoning: Bool = true,
        sessionHistoryLimit: Int? = 50,
        contextMode: ContextMode = .adaptive,
        parallelToolCalls: Bool = false,
        previousResponseId: String? = nil,
        autoPreviousResponseId: Bool = false,
        defaultTracingEnabled: Bool = true
    ) {
        if maxIterations < 1 {
            Log.agents.warning("AgentConfiguration: maxIterations \(maxIterations) must be >= 1; using 1")
        }
        if timeout <= .zero {
            Log.agents.warning("AgentConfiguration: timeout must be positive; using default 60 seconds")
        }
        if !temperature.isFinite || !(0.0 ... 2.0).contains(temperature) {
            Log.agents.warning("AgentConfiguration: temperature \(temperature) out of [0.0, 2.0]; using default 1.0")
        }
        self.name = name
        self.maxIterations = max(1, maxIterations)
        self.timeout = timeout > .zero ? timeout : .seconds(60)
        self.temperature = (temperature.isFinite && (0.0 ... 2.0).contains(temperature)) ? temperature : 1.0
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.modelSettings = modelSettings
        self.contextProfile = contextProfile
        self.graphRunOptionsOverride = nil
        self.inferencePolicy = inferencePolicy
        self.enableStreaming = enableStreaming
        self.includeToolCallDetails = includeToolCallDetails
        self.stopOnToolError = stopOnToolError
        self.includeReasoning = includeReasoning
        self.sessionHistoryLimit = sessionHistoryLimit
        self.contextMode = contextMode
        self.parallelToolCalls = parallelToolCalls
        self.previousResponseId = previousResponseId
        self.autoPreviousResponseId = autoPreviousResponseId
        self.defaultTracingEnabled = defaultTracingEnabled
    }
}

// MARK: - Builder Modifier Methods

/// Fluent copy-and-set modifiers. Each returns a new configuration with the
/// named property updated; the receiver is unchanged. See individual
/// properties above for semantics.
public extension AgentConfiguration {
    @discardableResult func name(_ value: String) -> AgentConfiguration {
        var copy = self
        copy.name = value
        return copy
    }

    @discardableResult func maxIterations(_ value: Int) -> AgentConfiguration {
        var copy = self
        copy.maxIterations = value
        return copy
    }

    @discardableResult func timeout(_ value: Duration) -> AgentConfiguration {
        var copy = self
        copy.timeout = value
        return copy
    }

    @discardableResult func temperature(_ value: Double) -> AgentConfiguration {
        var copy = self
        copy.temperature = value
        return copy
    }

    @discardableResult func maxTokens(_ value: Int?) -> AgentConfiguration {
        var copy = self
        copy.maxTokens = value
        return copy
    }

    @discardableResult func stopSequences(_ value: [String]) -> AgentConfiguration {
        var copy = self
        copy.stopSequences = value
        return copy
    }

    @discardableResult func modelSettings(_ value: ModelSettings?) -> AgentConfiguration {
        var copy = self
        copy.modelSettings = value
        return copy
    }

    @discardableResult func contextProfile(_ value: ContextProfile) -> AgentConfiguration {
        var copy = self
        copy.contextProfile = value
        return copy
    }

    @discardableResult func contextMode(_ value: ContextMode) -> AgentConfiguration {
        var copy = self
        copy.contextMode = value
        return copy
    }

    @discardableResult func inferencePolicy(_ value: InferencePolicy?) -> AgentConfiguration {
        var copy = self
        copy.inferencePolicy = value
        return copy
    }

    @discardableResult func enableStreaming(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.enableStreaming = value
        return copy
    }

    @discardableResult func includeToolCallDetails(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.includeToolCallDetails = value
        return copy
    }

    @discardableResult func stopOnToolError(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.stopOnToolError = value
        return copy
    }

    @discardableResult func includeReasoning(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.includeReasoning = value
        return copy
    }

    @discardableResult func sessionHistoryLimit(_ value: Int?) -> AgentConfiguration {
        var copy = self
        copy.sessionHistoryLimit = value
        return copy
    }

    @discardableResult func parallelToolCalls(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.parallelToolCalls = value
        return copy
    }

    @discardableResult func previousResponseId(_ value: String?) -> AgentConfiguration {
        var copy = self
        copy.previousResponseId = value
        return copy
    }

    @discardableResult func autoPreviousResponseId(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.autoPreviousResponseId = value
        return copy
    }

    @discardableResult func defaultTracingEnabled(_ value: Bool) -> AgentConfiguration {
        var copy = self
        copy.defaultTracingEnabled = value
        return copy
    }
}

// MARK: - CustomStringConvertible

extension AgentConfiguration: CustomStringConvertible {
    public var description: String {
        """
        AgentConfiguration(
            name: "\(name)",
            maxIterations: \(maxIterations),
            timeout: \(timeout),
            temperature: \(temperature),
            maxTokens: \(maxTokens.map(String.init) ?? "nil"),
            stopSequences: \(stopSequences),
            modelSettings: \(modelSettings.map { String(describing: $0) } ?? "nil"),
            contextProfile: \(contextProfile),
            graphRunOptionsOverride: \(graphRunOptionsOverride.map { String(describing: $0) } ?? "nil"),
            inferencePolicy: \(inferencePolicy.map { String(describing: $0) } ?? "nil"),
            enableStreaming: \(enableStreaming),
            includeToolCallDetails: \(includeToolCallDetails),
            stopOnToolError: \(stopOnToolError),
            includeReasoning: \(includeReasoning),
            sessionHistoryLimit: \(sessionHistoryLimit.map(String.init) ?? "nil"),
            contextMode: \(contextMode),
            parallelToolCalls: \(parallelToolCalls),
            previousResponseId: \(previousResponseId.map { "\"\($0)\"" } ?? "nil"),
            autoPreviousResponseId: \(autoPreviousResponseId),
            defaultTracingEnabled: \(defaultTracingEnabled)
        )
        """
    }
}
