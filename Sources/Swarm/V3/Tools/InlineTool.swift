// InlineTool.swift
// Swarm V3 API
//
// Closure-based one-off tool for inline definitions.

import Foundation

// MARK: - InlineTool

/// A closure-based tool for one-off definitions without a dedicated struct.
public struct InlineTool<Input: Codable & Sendable>: ToolV3 {
    public let toolName: String
    public let toolDescription: String
    private let _execute: @Sendable (Input) async throws -> String

    // Static conformance (instance-level names used at runtime)
    public static var name: String { "" }
    public static var description: String { "" }

    public init(
        _ name: String,
        _ description: String,
        execute: @escaping @Sendable (Input) async throws -> String
    ) {
        self.toolName = name
        self.toolDescription = description
        self._execute = execute
    }

    /// Execute with typed input.
    public func execute(input: Input) async throws -> String {
        try await _execute(input)
    }

    /// ToolV3 conformance — not called directly for InlineTool.
    public func call() async throws -> String {
        fatalError("InlineTool.call() requires typed input — use execute(input:)")
    }

    public func toAnyJSONTool() -> any AnyJSONTool {
        InlineAnyJSONTool(
            name: toolName,
            description: toolDescription
        ) { args in
            guard let first = args.values.first, case .string(let s) = first else {
                throw AgentError.toolExecutionFailed(
                    toolName: self.toolName,
                    underlyingError: "Expected string input"
                )
            }
            // swiftlint:disable:next force_cast
            let result = try await self._execute(s as! Input)
            return .string(result)
        }
    }
}

// MARK: - InlineAnyJSONTool (internal bridge)

struct InlineAnyJSONTool: AnyJSONTool {
    let name: String
    let description: String
    let parameters: [ToolParameter] = []
    private let _execute: @Sendable ([String: SendableValue]) async throws -> SendableValue

    init(
        name: String,
        description: String,
        execute: @escaping @Sendable ([String: SendableValue]) async throws -> SendableValue
    ) {
        self.name = name
        self.description = description
        self._execute = execute
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await _execute(arguments)
    }
}
