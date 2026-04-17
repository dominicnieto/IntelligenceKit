// InputGuardrail.swift
// Swarm Framework
//
// Input validation guardrails for agent systems.
// Provides validation and safety checks for agent inputs before processing.

import Foundation

/// Closure shape for ``InputGuard`` validation handlers. Receives the input
/// and optional ``AgentContext``, returns ``GuardrailResult``.
public typealias InputValidationHandler = @Sendable (String, AgentContext?) async throws -> GuardrailResult

// MARK: - InputGuardrail

/// Validates user input *before* the agent processes it. Returns
/// ``GuardrailResult/passed(message:outputInfo:metadata:)`` to allow the turn
/// to proceed, or ``GuardrailResult/tripwire(message:outputInfo:metadata:)``
/// to block it — the runner translates a tripwire into
/// ``GuardrailError/inputTripwireTriggered(guardrailName:message:outputInfo:)``.
///
/// See <doc:Guardrails> for patterns: length limits, rate limiting,
/// prompt-injection detection, composing multiple checks.
///
/// ## See Also
/// - ``InputGuard``
/// - ``OutputGuardrail``
/// - ``GuardrailResult``
/// - ``GuardrailError``
public protocol InputGuardrail: Guardrail {
    /// Evaluates `input` and returns a result. Only throw for unexpected
    /// failures (network, storage) — use `.tripwire(...)` for validation
    /// failures so the runner can attribute them cleanly.
    func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - InputGuard

/// Closure-based ``InputGuardrail``. Use the static factories
/// (``maxLength(_:name:)``, ``notEmpty(name:)``, ``custom(_:_:)``) for common
/// checks, or one of the two initializers for inline closures.
public struct InputGuard: InputGuardrail, Sendable {
    /// Unique name, used in logging and ``GuardrailError`` payloads.
    public let name: String

    /// Creates a guard whose validation only inspects the input text.
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { input, _ in
            try await validate(input)
        }
    }

    /// Creates a guard that also receives the ``AgentContext`` — useful for
    /// rate limiting, feature flags, or any decision keyed on shared state.
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = validate
    }

    public func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(input, context)
    }

    private let handler: InputValidationHandler
}

// MARK: - InputGuard Static Factories

public extension InputGuard {
    /// Trips when `input.count > maxLength`. The tripwire metadata carries
    /// the actual length and the limit.
    static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.count > maxLength {
                return .tripwire(
                    message: "Input exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(input.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Trips when the input is empty or whitespace/newline-only.
    static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .tripwire(message: "Input cannot be empty")
            }
            return .passed()
        }
    }

    /// Creates a named guard around an ad-hoc validation closure.
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard(name, validate)
    }
}

// MARK: - Protocol Extension Factory Methods

extension InputGuardrail where Self == InputGuard {
    /// Protocol-extension re-export of ``InputGuard/maxLength(_:name:)`` so
    /// you can write `.maxLength(...)` in an `[any InputGuardrail]` literal.
    public static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard.maxLength(maxLength, name: name)
    }

    /// Protocol-extension re-export of ``InputGuard/notEmpty(name:)``.
    public static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard.notEmpty(name: name)
    }

    /// Protocol-extension re-export of ``InputGuard/custom(_:_:)``.
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard.custom(name, validate)
    }
}
