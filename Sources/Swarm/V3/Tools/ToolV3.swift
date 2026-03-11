// ToolV3.swift
// Swarm V3 API
//
// User-facing tool protocol and @ParameterV3 property wrapper.

import Foundation

// MARK: - @ParameterV3

/// Property wrapper for declaring tool parameters with descriptions.
@propertyWrapper
public struct ParameterV3<Value: Sendable>: Sendable {
    public var wrappedValue: Value
    public let description: String

    public init(wrappedValue: Value, _ description: String) {
        self.wrappedValue = wrappedValue
        self.description = description
    }
}

extension ParameterV3 where Value: ExpressibleByNilLiteral {
    public init(_ description: String) {
        self.wrappedValue = nil
        self.description = description
    }
}

// MARK: - ToolV3

/// User-facing tool protocol. No associated types — safe as existential `[any ToolV3]`.
public protocol ToolV3: Sendable {
    /// The unique name of this tool.
    static var name: String { get }

    /// Human-readable description.
    static var description: String { get }

    /// Execute the tool and return a string result.
    func call() async throws -> String

    /// Bridge to the existing AnyJSONTool wire protocol.
    func toAnyJSONTool() -> any AnyJSONTool
}
