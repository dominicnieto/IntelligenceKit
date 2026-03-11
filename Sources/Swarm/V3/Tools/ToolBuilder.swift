// ToolBuilder.swift
// Swarm V3 API
//
// Result builder for composing tools in a trailing closure.

// MARK: - @ToolBuilder

/// Result builder that collects `ToolV3` instances into an array.
@resultBuilder
public struct ToolBuilder {
    public static func buildBlock(_ components: [any ToolV3]...) -> [any ToolV3] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: any ToolV3) -> [any ToolV3] {
        [expression]
    }

    public static func buildArray(_ components: [[any ToolV3]]) -> [any ToolV3] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any ToolV3]?) -> [any ToolV3] {
        component ?? []
    }

    public static func buildEither(first component: [any ToolV3]) -> [any ToolV3] {
        component
    }

    public static func buildEither(second component: [any ToolV3]) -> [any ToolV3] {
        component
    }
}
