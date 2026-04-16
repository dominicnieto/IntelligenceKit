// AgentError.swift
// Swarm Framework
//
// Comprehensive error types for agent operations.

import Foundation

// MARK: - AgentError

/// Errors that can occur during agent execution.
///
/// ```swift
/// do {
///     let result = try await agent.run("Task")
/// } catch let error as AgentError {
///     switch error {
///     case .maxIterationsExceeded:
///         print("Agent needed more iterations")
///     case .toolExecutionFailed(let name, let underlying):
///         print("Tool '\(name)' failed: \(underlying)")
///     default:
///         print("Error: \(error.localizedDescription)")
///     }
/// }
/// ```
///
/// For recovery patterns (retry, backoff, fallback providers, context-window
/// management) see the article <doc:ErrorHandling>. ``recoverySuggestion``
/// returns a short hint suitable for surfacing to users.
///
/// ## See Also
/// - ``GuardrailError``
/// - ``WorkflowError``
public enum AgentError: Error, Sendable, Equatable {

    // MARK: - Input Errors

    /// Input was empty, whitespace-only, or otherwise rejected.
    case invalidInput(reason: String)

    // MARK: - Execution Errors

    /// The agent was cancelled before completion. Non-retryable.
    case cancelled

    /// The agent performed more reasoning steps than `maxIterations` allows.
    case maxIterationsExceeded(iterations: Int)

    /// The agent exceeded its configured `timeout`.
    case timeout(duration: Duration)

    /// The agent's declarative loop configuration is invalid.
    case invalidLoop(reason: String)

    // MARK: - Tool Errors

    /// A tool requested by the model isn't registered on this agent.
    case toolNotFound(name: String)

    /// A tool's `execute` threw or returned an unexpected result.
    /// - Parameter underlyingError: string description of the underlying failure
    case toolExecutionFailed(toolName: String, underlyingError: String)

    /// The model produced tool arguments that failed schema validation.
    case invalidToolArguments(toolName: String, reason: String)

    // MARK: - Model Errors

    /// No inference provider could be resolved, or the resolved one is unreachable.
    case inferenceProviderUnavailable(reason: String)

    /// Total token count exceeded the model's context window.
    case contextWindowExceeded(tokenCount: Int, limit: Int)

    /// The response was blocked by a configured guardrail (application-defined).
    /// Contrast with ``contentFiltered(reason:)``.
    case guardrailViolation(reason: String)

    /// The provider's own safety system filtered the content. Contrast with
    /// ``guardrailViolation(reason:)``.
    case contentFiltered(reason: String)

    /// The model does not support the requested language.
    case unsupportedLanguage(language: String)

    /// The provider reported an internal failure during generation. Often transient.
    case generationFailed(reason: String)

    /// The named model is unknown, deprecated, or not accessible with the current credentials.
    case modelNotAvailable(model: String)

    // MARK: - Rate Limiting Errors

    /// Provider rate limit was hit.
    /// - Parameter retryAfter: recommended delay in seconds, or `nil` if the
    ///   provider didn't supply one
    case rateLimitExceeded(retryAfter: TimeInterval?)

    // MARK: - Embedding Errors

    /// Text embedding generation failed.
    case embeddingFailed(reason: String)

    // MARK: - Internal Errors

    /// A handoff referenced an agent name that isn't registered.
    case agentNotFound(name: String)

    /// An unexpected internal failure. Usually indicates a framework bug.
    case internalError(reason: String)

    /// Tool calling was requested but the resolved provider path can't satisfy it.
    /// Configure a cloud provider via `Swarm.configure(cloudProvider:)` or enable
    /// prompt-based emulation. See ``recoverySuggestion`` for the default hint.
    case toolCallingRequiresCloudProvider
}

// MARK: - LocalizedError

extension AgentError: LocalizedError {

    /// Human-readable description suitable for UI alerts or logs.
    public var errorDescription: String? {
        switch self {
        case let .invalidInput(reason):
            "Invalid input: \(reason)"
        case .cancelled:
            "Agent execution was cancelled"
        case let .maxIterationsExceeded(iterations):
            "Agent exceeded maximum iterations (\(iterations))"
        case let .timeout(duration):
            "Agent execution timed out after \(duration)"
        case let .invalidLoop(reason):
            "Invalid agent loop: \(reason)"
        case let .toolNotFound(name):
            "Tool not found: \(name)"
        case let .toolExecutionFailed(toolName, underlyingError):
            "Tool '\(toolName)' failed: \(underlyingError)"
        case let .invalidToolArguments(toolName, reason):
            "Invalid arguments for tool '\(toolName)': \(reason)"
        case let .inferenceProviderUnavailable(reason):
            "Inference provider unavailable: \(reason)"
        case let .contextWindowExceeded(count, limit):
            "Context window exceeded: \(count) tokens (limit: \(limit))"
        case let .guardrailViolation(reason):
            "Response violated content guidelines: \(reason)"
        case let .contentFiltered(reason):
            "Content filtered: \(reason)"
        case let .unsupportedLanguage(language):
            "Language not supported: \(language)"
        case let .generationFailed(reason):
            "Generation failed: \(reason)"
        case let .modelNotAvailable(model):
            "Model not available: \(model)"
        case let .rateLimitExceeded(retryAfter):
            if let retryAfter {
                "Rate limit exceeded, retry after \(retryAfter) seconds"
            } else {
                "Rate limit exceeded"
            }
        case let .embeddingFailed(reason):
            "Embedding failed: \(reason)"
        case let .agentNotFound(name):
            "Agent not found: '\(name)'"
        case let .internalError(reason):
            "Internal error: \(reason)"
        case .toolCallingRequiresCloudProvider:
            "The selected provider could not satisfy this tool calling request."
        }
    }

    /// Actionable recovery hint for cases where one is meaningful; `nil` otherwise.
    public var recoverySuggestion: String? {
        switch self {
        case .toolCallingRequiresCloudProvider:
            "Configure `Swarm.configure(cloudProvider:)` or pass a provider with native tool-calling support if this request cannot rely on prompt-based tool emulation."
        case .inferenceProviderUnavailable:
            "Check your network connection and API credentials, or try again later."
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                "Wait \(Int(seconds)) seconds before retrying the request."
            } else {
                "Wait a moment before retrying the request."
            }
        case .contextWindowExceeded:
            "Reduce the conversation history length or use a model with a larger context window."
        case .toolNotFound(let name):
            "Ensure the tool '\(name)' is registered with the agent and the name is spelled correctly."
        case .modelNotAvailable(let model):
            "Check that '\(model)' is a valid model name and your API key has access to it."
        case .maxIterationsExceeded:
            "Increase the maxIterations configuration or break the task into smaller subtasks."
        case .timeout:
            "Increase the timeout duration or optimize the task to complete faster."
        case .invalidToolArguments(let toolName, _):
            "Review the tool '\(toolName)' documentation and ensure all required parameters are provided."
        default:
            nil
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension AgentError: CustomDebugStringConvertible {

    /// Debug description including all associated values.
    public var debugDescription: String {
        switch self {
        case let .invalidInput(reason):
            "AgentError.invalidInput(reason: \(reason))"
        case .cancelled:
            "AgentError.cancelled"
        case let .maxIterationsExceeded(iterations):
            "AgentError.maxIterationsExceeded(iterations: \(iterations))"
        case let .timeout(duration):
            "AgentError.timeout(duration: \(duration))"
        case let .invalidLoop(reason):
            "AgentError.invalidLoop(reason: \(reason))"
        case let .toolNotFound(name):
            "AgentError.toolNotFound(name: \(name))"
        case let .toolExecutionFailed(toolName, underlyingError):
            "AgentError.toolExecutionFailed(toolName: \(toolName), underlyingError: \(underlyingError))"
        case let .invalidToolArguments(toolName, reason):
            "AgentError.invalidToolArguments(toolName: \(toolName), reason: \(reason))"
        case let .inferenceProviderUnavailable(reason):
            "AgentError.inferenceProviderUnavailable(reason: \(reason))"
        case let .contextWindowExceeded(tokenCount, limit):
            "AgentError.contextWindowExceeded(tokenCount: \(tokenCount), limit: \(limit))"
        case let .guardrailViolation(reason):
            "AgentError.guardrailViolation(reason: \(reason))"
        case let .contentFiltered(reason):
            "AgentError.contentFiltered(reason: \(reason))"
        case let .unsupportedLanguage(language):
            "AgentError.unsupportedLanguage(language: \(language))"
        case let .generationFailed(reason):
            "AgentError.generationFailed(reason: \(reason))"
        case let .modelNotAvailable(model):
            "AgentError.modelNotAvailable(model: \(model))"
        case let .rateLimitExceeded(retryAfter):
            "AgentError.rateLimitExceeded(retryAfter: \(String(describing: retryAfter)))"
        case let .embeddingFailed(reason):
            "AgentError.embeddingFailed(reason: \(reason))"
        case let .agentNotFound(name):
            "AgentError.agentNotFound(name: \(name))"
        case let .internalError(reason):
            "AgentError.internalError(reason: \(reason))"
        case .toolCallingRequiresCloudProvider:
            "AgentError.toolCallingRequiresCloudProvider"
        }
    }
}
