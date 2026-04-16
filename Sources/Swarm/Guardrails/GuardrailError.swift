// GuardrailError.swift
// Swarm Framework
//
// Comprehensive error types for guardrail execution.

import Foundation

// MARK: - GuardrailError

/// Errors raised when a guardrail tripwire fires or a guardrail's body throws.
///
/// ```swift
/// do {
///     let result = try await agent.run(input)
/// } catch let error as GuardrailError {
///     print("Guardrail stopped execution: \(error.localizedDescription)")
/// }
/// ```
///
/// ## See Also
/// - ``AgentError``
/// - ``WorkflowError``
/// - <doc:ErrorHandling>
public enum GuardrailError: Error, Sendable, LocalizedError, Equatable {
    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .inputTripwireTriggered(name, message, _):
            "Input guardrail '\(name)' tripwire triggered: \(message ?? "No message")"
        case let .outputTripwireTriggered(name, agentName, message, _):
            "Output guardrail '\(name)' tripwire triggered for agent '\(agentName)': \(message ?? "No message")"
        case let .toolInputTripwireTriggered(name, toolName, message, _):
            "Tool input guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message ?? "No message")"
        case let .toolOutputTripwireTriggered(name, toolName, message, _):
            "Tool output guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message ?? "No message")"
        case let .executionFailed(name, error):
            "Guardrail '\(name)' execution failed: \(error)"
        }
    }

    /// An input guardrail tripped before the agent processed the user's request.
    /// - Parameter outputInfo: arbitrary diagnostic payload from the guardrail, if any
    case inputTripwireTriggered(
        guardrailName: String,
        message: String?,
        outputInfo: SendableValue?
    )

    /// An output guardrail tripped on the agent's response before it was returned.
    /// - Parameter outputInfo: arbitrary diagnostic payload from the guardrail, if any
    case outputTripwireTriggered(
        guardrailName: String,
        agentName: String,
        message: String?,
        outputInfo: SendableValue?
    )

    /// A tool-input guardrail tripped on arguments the model generated for a tool.
    /// - Parameter outputInfo: arbitrary diagnostic payload from the guardrail, if any
    case toolInputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String?,
        outputInfo: SendableValue?
    )

    /// A tool-output guardrail tripped on a tool's result before it was fed back to the model.
    /// - Parameter outputInfo: arbitrary diagnostic payload from the guardrail, if any
    case toolOutputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String?,
        outputInfo: SendableValue?
    )

    /// The guardrail's own body threw while evaluating.
    case executionFailed(guardrailName: String, underlyingError: String)
}

// MARK: CustomDebugStringConvertible

extension GuardrailError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .inputTripwireTriggered(name, message, outputInfo):
            return "GuardrailError.inputTripwireTriggered(guardrailName: \(name), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .outputTripwireTriggered(name, agentName, message, outputInfo):
            return "GuardrailError.outputTripwireTriggered(guardrailName: \(name), agentName: \(agentName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .toolInputTripwireTriggered(name, toolName, message, outputInfo):
            return "GuardrailError.toolInputTripwireTriggered(guardrailName: \(name), toolName: \(toolName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .toolOutputTripwireTriggered(name, toolName, message, outputInfo):
            return "GuardrailError.toolOutputTripwireTriggered(guardrailName: \(name), toolName: \(toolName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .executionFailed(name, error):
            return "GuardrailError.executionFailed(guardrailName: \(name), underlyingError: \(error))"
        }
    }
}
