// OutputGuardrail.swift
// Swarm Framework
//
// Protocol and implementations for validating agent output before returning to users.

import Foundation

/// Closure shape for ``OutputGuard`` validation handlers. Receives the agent
/// output, the producing ``AgentRuntime``, and optional ``AgentContext``,
/// returns ``GuardrailResult``.
public typealias OutputValidationHandler = @Sendable (String, any AgentRuntime, AgentContext?) async throws -> GuardrailResult

// MARK: - OutputGuardrail

/// Validates an agent's response *before* it's returned to the caller.
/// Returns ``GuardrailResult/passed(message:outputInfo:metadata:)`` to let the
/// output through, or ``GuardrailResult/tripwire(message:outputInfo:metadata:)``
/// to block it — the runner translates a tripwire into
/// ``GuardrailError/outputTripwireTriggered(guardrailName:agentName:message:outputInfo:)``.
///
/// See <doc:Guardrails> for patterns: PII redaction, length limits, format
/// validation, agent-scoped checks.
///
/// ## See Also
/// - ``OutputGuard``
/// - ``InputGuardrail``
/// - ``GuardrailResult``
/// - ``GuardrailError``
public protocol OutputGuardrail: Guardrail {
    /// Evaluates `output`. The `agent` parameter is the ``AgentRuntime`` that
    /// produced the output — use `agent.configuration` (e.g. `.name`) for
    /// agent-scoped validation. Only throw for unexpected failures; use
    /// `.tripwire(...)` for validation failures.
    func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - OutputGuard

/// Closure-based ``OutputGuardrail``. Three init overloads trade progressive
/// access for ergonomics: output-only, `(output, context)`, and full
/// `(output, agent, context)`. Use the static factories
/// (``maxLength(_:name:)``, ``custom(_:_:)``) for common checks.
public struct OutputGuard: OutputGuardrail, Sendable {
    /// Unique name, used in logging and ``GuardrailError`` payloads.
    public let name: String

    /// Creates a guard whose validation only inspects the output text.
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, _ in
            try await validate(output)
        }
    }

    /// Creates a guard that also receives the ``AgentContext`` for decisions
    /// keyed on shared state.
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, context in
            try await validate(output, context)
        }
    }

    /// Creates a guard that additionally receives the producing
    /// ``AgentRuntime`` — use for agent-scoped rules.
    public init(
        _ name: String,
        _ validate: @escaping OutputValidationHandler
    ) {
        self.name = name
        handler = validate
    }

    public func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(output, agent, context)
    }

    private let handler: OutputValidationHandler
}

// MARK: - OutputGuard Static Factories

public extension OutputGuard {
    /// Trips when `output.count > maxLength`. The tripwire metadata carries
    /// the actual length and the limit.
    static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard(name) { output in
            if output.count > maxLength {
                return .tripwire(
                    message: "Output exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(output.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Creates a named guard around an ad-hoc validation closure.
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard(name, validate)
    }
}

// MARK: - Protocol Extension Factory Methods

extension OutputGuardrail where Self == OutputGuard {
    /// Protocol-extension re-export of ``OutputGuard/maxLength(_:name:)`` so
    /// you can write `.maxLength(...)` in an `[any OutputGuardrail]` literal.
    public static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard.maxLength(maxLength, name: name)
    }

    /// Protocol-extension re-export of ``OutputGuard/custom(_:_:)``.
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard.custom(name, validate)
    }
}
