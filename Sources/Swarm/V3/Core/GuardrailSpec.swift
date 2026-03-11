// GuardrailSpec.swift
// Swarm V3 API
//
// Single enum replacing 14 guardrail protocol/builder/closure types.

import Foundation

// MARK: - GuardrailSpec

/// Unified guardrail specification. Replaces 14 separate guardrail types.
///
/// Returns `nil` on pass, a block-reason `String` on failure.
public enum GuardrailSpec: Sendable {
    // Input guardrails
    case maxInput(characters: Int)
    case inputNotEmpty
    case inputCustom(name: String, validate: @Sendable (String) async throws -> String?)

    // Output guardrails
    case maxOutput(characters: Int)
    case outputCustom(name: String, validate: @Sendable (String) async throws -> String?)

    /// Validate input. Returns `nil` if valid, block reason if not.
    public func validateInput(_ input: String) async throws -> String? {
        switch self {
        case .maxInput(let max):
            return input.count > max
                ? "Input exceeds \(max) characters (\(input.count))"
                : nil
        case .inputNotEmpty:
            return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Input must not be empty"
                : nil
        case .inputCustom(_, let validate):
            return try await validate(input)
        default:
            return nil
        }
    }

    /// Validate output. Returns `nil` if valid, block reason if not.
    public func validateOutput(_ output: String) async throws -> String? {
        switch self {
        case .maxOutput(let max):
            return output.count > max
                ? "Output exceeds \(max) characters (\(output.count))"
                : nil
        case .outputCustom(_, let validate):
            return try await validate(output)
        default:
            return nil
        }
    }
}
