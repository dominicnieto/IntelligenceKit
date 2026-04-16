// Tool.swift
// Swarm Framework
//
// Dynamic (JSON) tool protocol and supporting types for tool execution.

import Foundation

// MARK: - AnyJSONTool

/// Type-erased wire protocol that the runtime uses to execute tools without
/// knowing their concrete `Input`/`Output` types.
///
/// Most users define tools via the `@Tool` macro on a ``Tool`` conformance; the
/// macro synthesizes the `AnyJSONTool` adapter automatically. Implement this
/// protocol directly only when you need dynamic, schema-driven tool behavior
/// that the typed ``Tool`` protocol can't express.
///
/// See <doc:ToolAuthoring> for worked examples (`@Tool`, manual conformance,
/// `FunctionTool`, dynamic `AnyJSONTool`).
///
/// ## See Also
/// - ``Tool``
/// - ``ToolSchema``
/// - ``ToolParameter``
/// - ``FunctionTool``
public protocol AnyJSONTool: Sendable {
    /// Unique tool name. `snake_case` by convention — used as the registry key
    /// and sent verbatim in provider tool schemas.
    var name: String { get }

    /// Human-readable description used in provider tool schemas. The model relies
    /// on this to decide when to call the tool.
    var description: String { get }

    /// Parameter schema for ``execute(arguments:)``.
    var parameters: [ToolParameter] { get }

    /// Guardrails that run against the model-generated arguments before execution.
    var inputGuardrails: [any ToolInputGuardrail] { get }

    /// Guardrails that run against the tool's result before it's returned to the model.
    var outputGuardrails: [any ToolOutputGuardrail] { get }

    /// Execution semantics — determinism, side effects, caching hints for the runtime.
    var executionSemantics: ToolExecutionSemantics { get }

    /// When `false`, the tool is hidden from provider schemas and calls to it
    /// raise ``AgentError/toolNotFound(name:)``.
    var isEnabled: Bool { get }

    /// Executes the tool. Arguments have already been validated against
    /// ``parameters`` by the runtime.
    /// - Throws: ``AgentError/toolExecutionFailed(toolName:underlyingError:)`` or
    ///   ``AgentError/invalidToolArguments(toolName:reason:)``; implementations
    ///   may also throw their own errors.
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}

// MARK: - AnyJSONTool Protocol Extensions

public extension AnyJSONTool {
    /// Materialized ``ToolSchema`` used when sending tool definitions to providers.
    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            parameters: parameters,
            executionSemantics: executionSemantics
        )
    }

    var inputGuardrails: [any ToolInputGuardrail] { [] }

    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    var isEnabled: Bool { true }

    var executionSemantics: ToolExecutionSemantics { .automatic }

    /// Checks required parameters are present and values match expected types.
    /// - Throws: ``AgentError/invalidToolArguments(toolName:reason:)``
    func validateArguments(_ arguments: [String: SendableValue]) throws {
        try ToolArgumentProcessor.validate(
            toolName: name,
            parameters: parameters,
            arguments: arguments
        )
    }

    /// Applies parameter defaults and best-effort coercion (e.g. `"42"` → `42`)
    /// to model-generated arguments, then validates.
    /// - Throws: ``AgentError/invalidToolArguments(toolName:reason:)``
    func normalizeArguments(_ arguments: [String: SendableValue]) throws -> [String: SendableValue] {
        try ToolArgumentProcessor.normalize(
            toolName: name,
            parameters: parameters,
            arguments: arguments
        )
    }

    /// Extracts a required string argument.
    /// - Throws: ``AgentError/invalidToolArguments(toolName:reason:)`` if missing or wrong type
    func requiredString(_ key: String, from arguments: [String: SendableValue]) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing or invalid string parameter: \(key)"
            )
        }
        return value
    }

    /// Extracts an optional string argument, falling back to `defaultValue` if missing.
    func optionalString(_ key: String, from arguments: [String: SendableValue], default defaultValue: String? = nil) -> String? {
        arguments[key]?.stringValue ?? defaultValue
    }
}

// MARK: - Tool (Typed Protocol)

/// Typed, `Codable`-based tool protocol — the primary way to define tools in Swarm.
///
/// Prefer the `@Tool` macro, which synthesizes `Input`, `parameters`, and the
/// `AnyJSONTool` adapter from `@Parameter`-annotated properties:
///
/// ```swift
/// @Tool("Gets current weather for a city")
/// struct GetWeather {
///     @Parameter("City name, e.g. 'San Francisco'")
///     var city: String
///
///     func execute() async throws -> String { /* ... */ }
/// }
/// ```
///
/// Conform manually when the macro can't express what you need — see
/// <doc:ToolAuthoring> for a mortgage-calculator example and guidance on
/// when to fall back to ``AnyJSONTool`` directly.
///
/// ## See Also
/// - ``AnyJSONTool``
/// - ``ToolParameter``
/// - <doc:ToolAuthoring>
public protocol Tool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Encodable & Sendable

    /// Unique tool name. `snake_case` by convention.
    var name: String { get }

    /// Description used in provider tool schemas. The model decides when to
    /// call the tool based on this text.
    var description: String { get }

    /// Parameter schema. The `@Tool` macro generates this from `@Parameter` wrappers.
    var parameters: [ToolParameter] { get }

    var inputGuardrails: [any ToolInputGuardrail] { get }
    var outputGuardrails: [any ToolOutputGuardrail] { get }
    var executionSemantics: ToolExecutionSemantics { get }

    /// Executes with a decoded, typed input.
    func execute(_ input: Input) async throws -> Output
}

public extension Tool {
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }
    var executionSemantics: ToolExecutionSemantics { .automatic }

    /// Materialized ``ToolSchema`` used when sending tool definitions to providers.
    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            parameters: parameters,
            executionSemantics: executionSemantics
        )
    }
}

// MARK: - ToolArgumentProcessor

/// Shared argument validation + normalization logic for `AnyJSONTool`.
private enum ToolArgumentProcessor {
    // MARK: Internal

    /// Maximum recursion depth for nested object/array parameters to prevent stack overflow.
    static let maxDepth = 50

    static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws {
        try validate(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws -> [String: SendableValue] {
        try normalize(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    // MARK: Private

    private static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

        for param in parameters where param.isRequired {
            guard arguments[param.name] != nil else {
                let fullPath = join(pathPrefix, param.name)
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Missing required parameter: \(fullPath)"
                )
            }
        }

        for param in parameters {
            guard let value = arguments[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            try validateValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }
    }

    private static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws -> [String: SendableValue] {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

        var normalized = arguments

        // Apply default values (also when model explicitly sends null)
        for param in parameters {
            let currentValue = normalized[param.name]
            if currentValue == nil || currentValue == .null, let defaultValue = param.defaultValue {
                normalized[param.name] = defaultValue
            }
        }

        // Coerce known parameters to expected types
        for param in parameters {
            guard let value = normalized[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            normalized[param.name] = try coerceValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }

        // Validate after applying defaults + coercion
        try validate(toolName: toolName, parameters: parameters, arguments: normalized, pathPrefix: pathPrefix, depth: depth)
        return normalized
    }

    private static func validateValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String,
        depth: Int = 0
    ) throws {
        switch expected {
        case .any:
            return

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .int:
            switch value {
            case .int:
                return
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case .double,
                 .int:
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            guard case .bool = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            for (index, element) in elements.enumerated() {
                try validateValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            try validate(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            guard options.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) else {
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
                )
            }
        }
    }

    private static func coerceValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String,
        depth: Int = 0
    ) throws -> SendableValue {
        switch expected {
        case .any:
            return value

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            return value

        case .int:
            switch value {
            case .int:
                return value
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return .int(Int(d))
            case let .string(s):
                if let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .int(i)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case let .double(d):
                return .double(d)
            case let .int(i):
                return .double(Double(i))
            case let .string(s):
                if let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .double(d)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            switch value {
            case .bool:
                return value
            case let .string(s):
                switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true":
                    return .bool(true)
                case "false":
                    return .bool(false)
                default:
                    throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
                }
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try elements.enumerated().map { index, element in
                try coerceValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }
            return .array(coerced)

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try normalize(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)
            return .dictionary(coerced)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            if let matched = options.first(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
                return .string(matched)
            }
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
            )
        }
    }

    private static func invalidType(
        toolName: String,
        path: String,
        expected: ToolParameter.ParameterType,
        actual: SendableValue
    ) -> AgentError {
        AgentError.invalidToolArguments(
            toolName: toolName,
            reason: "Invalid type for parameter: \(path). Expected \(expected.description), got \(jsonTypeDescription(actual))"
        )
    }

    private static func join(_ prefix: String?, _ key: String) -> String {
        guard let prefix, !prefix.isEmpty else { return key }
        return "\(prefix).\(key)"
    }

    private static func jsonTypeDescription(_ value: SendableValue) -> String {
        switch value {
        case .null:
            "null"
        case .bool:
            "boolean"
        case .int:
            "integer"
        case .double:
            "number"
        case .string:
            "string"
        case .array:
            "array"
        case .dictionary:
            "object"
        }
    }
}

// MARK: - ToolParameter

/// One parameter in a tool's input schema — name, description, type, and
/// optional default.
///
/// See <doc:ToolAuthoring> for patterns (simple types, arrays, nested objects,
/// string enums via ``ParameterType/oneOf(_:)``).
///
/// ## See Also
/// - ``ToolSchema``
/// - ``AnyJSONTool``
public struct ToolParameter: Sendable, Equatable {
    /// The shape of a parameter's value.
    indirect public enum ParameterType: Sendable, Equatable, CustomStringConvertible {
        case string
        case int
        case double
        case bool

        /// Ordered list with uniform element type.
        case array(elementType: ParameterType)

        /// Nested object with a declared property schema.
        case object(properties: [ToolParameter])

        /// String that must match one of the allowed values (case-insensitive).
        case oneOf([String])

        /// Any JSON-compatible value. Escape hatch for loose schemas.
        case any

        public var description: String {
            switch self {
            case .string: "string"
            case .int: "integer"
            case .double: "number"
            case .bool: "boolean"
            case let .array(elementType): "array<\(elementType)>"
            case .object: "object"
            case let .oneOf(options): "oneOf(\(options.joined(separator: "|")))"
            case .any: "any"
            }
        }
    }

    /// Parameter name, used as the argument-dictionary key. `snake_case` by convention.
    public let name: String

    /// Human-readable description sent to providers in tool schemas.
    public let description: String

    public let type: ParameterType

    public let isRequired: Bool

    /// Substituted when the parameter is omitted or explicitly `null`. Must be
    /// compatible with ``type``.
    public let defaultValue: SendableValue?

    public init(
        name: String,
        description: String,
        type: ParameterType,
        isRequired: Bool = true,
        defaultValue: SendableValue? = nil
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

// MARK: - ToolSchema

/// Provider-facing description of a tool — name, description, parameters, and
/// execution semantics. Usually obtained via the computed `schema` property on
/// ``AnyJSONTool`` or ``Tool`` rather than constructed directly.
///
/// ## See Also
/// - ``ToolParameter``
/// - ``AnyJSONTool``
/// - ``Tool``
public struct ToolSchema: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public let executionSemantics: ToolExecutionSemantics

    public init(
        name: String,
        description: String,
        parameters: [ToolParameter],
        executionSemantics: ToolExecutionSemantics = .automatic
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.executionSemantics = executionSemantics
    }
}

// MARK: - FunctionTool

/// Closure-based ``AnyJSONTool`` for quick one-off tools that don't warrant a
/// dedicated struct.
///
/// ```swift
/// let echo = FunctionTool(name: "echo", description: "Echoes input") { args in
///     let message = try args.require("message", as: String.self)
///     return .string("Echo: \(message)")
/// }
/// ```
///
/// For schema-driven examples (explicit parameters, enums, registration into
/// ``ToolRegistry``) see <doc:ToolAuthoring>.
///
/// ## See Also
/// - ``ToolArguments``
/// - ``AnyJSONTool``
/// - ``ToolRegistry``
public struct FunctionTool: AnyJSONTool, Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public let executionSemantics: ToolExecutionSemantics

    public init(
        name: String,
        description: String,
        parameters: [ToolParameter] = [],
        executionSemantics: ToolExecutionSemantics = .automatic,
        handler: @escaping @Sendable (ToolArguments) async throws -> SendableValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.executionSemantics = executionSemantics
        self.handler = handler
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await handler(ToolArguments(arguments, toolName: name))
    }

    // MARK: Private

    private let handler: @Sendable (ToolArguments) async throws -> SendableValue
}

// MARK: - ToolArguments

/// Type-safe accessor wrapper around a raw `[String: SendableValue]` argument
/// dictionary passed to ``FunctionTool`` handlers and custom ``AnyJSONTool``
/// implementations. Supports extraction of `String`, `Int`, `Double`, `Bool`.
///
/// ## See Also
/// - ``FunctionTool``
public struct ToolArguments: Sendable {
    public let raw: [String: SendableValue]

    /// Tool name used in argument-error messages.
    public let toolName: String

    public init(_ arguments: [String: SendableValue], toolName: String = "tool") {
        raw = arguments
        self.toolName = toolName
    }

    /// Extracts a required argument of the specified type.
    /// - Throws: ``AgentError/invalidToolArguments(toolName:reason:)`` if missing
    ///   or the value doesn't match `T`
    public func require<T>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = raw[key] else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Missing required argument: \(key)"
            )
        }

        let extracted: Any? = switch value {
        case let .string(s) where type == String.self: s
        case let .int(i) where type == Int.self: i
        case let .double(d) where type == Double.self: d
        case let .bool(b) where type == Bool.self: b
        default: nil
        }

        guard let result = extracted as? T else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Argument '\(key)' is not of type \(T.self)"
            )
        }
        return result
    }

    /// Extracts an optional argument, returning `nil` if absent or wrong type.
    public func optional<T>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let value = raw[key] else { return nil }
        return switch value {
        case let .string(s) where type == String.self: s as? T
        case let .int(i) where type == Int.self: i as? T
        case let .double(d) where type == Double.self: d as? T
        case let .bool(b) where type == Bool.self: b as? T
        default: nil
        }
    }

    /// Extracts a string argument, or `defaultValue` if absent/wrong-type.
    public func string(_ key: String, default defaultValue: String = "") -> String {
        raw[key]?.stringValue ?? defaultValue
    }

    /// Extracts an integer argument, or `defaultValue` if absent/wrong-type.
    public func int(_ key: String, default defaultValue: Int = 0) -> Int {
        raw[key]?.intValue ?? defaultValue
    }
}

// MARK: - ToolRegistry

public enum ToolRegistryError: Error, Sendable {
    /// A tool with this name is already registered.
    case duplicateToolName(name: String)
}

/// Actor-isolated registry of tools available to an agent. Handles lookup,
/// registration, and the full tool-execution lifecycle (normalize args →
/// input guardrails → execute → output guardrails).
///
/// ## See Also
/// - ``AnyJSONTool``
/// - ``Tool``
public actor ToolRegistry {
    /// All registered tools, enabled and disabled. For provider-facing tool
    /// lists use ``schemas`` which filters to enabled tools only.
    public var allTools: [any AnyJSONTool] {
        Array(tools.values)
    }

    public var toolNames: [String] {
        Array(tools.keys)
    }

    /// Schemas for enabled tools only — suitable for sending to providers.
    public var schemas: [ToolSchema] {
        tools.values.filter(\.isEnabled).map(\.schema)
    }

    public var count: Int {
        tools.count
    }

    public init() {}

    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on name collision
    public init(tools: [any AnyJSONTool]) throws {
        for tool in tools {
            guard self.tools[tool.name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: tool.name)
            }
            self.tools[tool.name] = tool
        }
    }

    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on name collision
    public init(tools: [some Tool]) throws {
        for tool in tools {
            let name = tool.name
            guard self.tools[name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: name)
            }
            self.tools[name] = AnyJSONToolAdapter(tool)
        }
    }

    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on name collision
    public func register(_ tool: any AnyJSONTool) throws {
        guard tools[tool.name] == nil else {
            throw ToolRegistryError.duplicateToolName(name: tool.name)
        }
        tools[tool.name] = tool
    }

    /// Registers a typed ``Tool`` by bridging through `AnyJSONToolAdapter`.
    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on name collision
    public func register(_ tool: some Tool) throws {
        let name = tool.name
        guard tools[name] == nil else {
            throw ToolRegistryError.duplicateToolName(name: name)
        }
        tools[name] = AnyJSONToolAdapter(tool)
    }

    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on the first collision
    public func register(_ newTools: [some Tool]) throws {
        for tool in newTools {
            let name = tool.name
            guard tools[name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: name)
            }
            tools[name] = AnyJSONToolAdapter(tool)
        }
    }

    /// - Throws: ``ToolRegistryError/duplicateToolName(name:)`` on the first collision
    public func register(_ newTools: [any AnyJSONTool]) throws {
        for tool in newTools {
            guard tools[tool.name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: tool.name)
            }
            tools[tool.name] = tool
        }
    }

    /// Removes a tool. Silently no-ops if no tool with that name is registered.
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
    }

    public func tool(named name: String) -> (any AnyJSONTool)? {
        tools[name]
    }

    /// Whether a tool with this name is registered (regardless of enabled state).
    public func contains(named name: String) -> Bool {
        tools[name] != nil
    }

    /// Runs the full tool execution pipeline: cancellation check, lookup,
    /// enabled-check, argument normalization, input guardrails, execute,
    /// output guardrails.
    /// - Throws: ``AgentError/toolNotFound(name:)`` when unknown or disabled,
    ///   ``AgentError/toolExecutionFailed(toolName:underlyingError:)`` when
    ///   execution throws a non-agent/guardrail error, ``GuardrailError`` for
    ///   tripped guardrails, or `CancellationError`
    public func execute(
        toolNamed name: String,
        arguments: [String: SendableValue],
        agent: (any AgentRuntime)? = nil,
        context: AgentContext? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> SendableValue {
        // Check for cancellation before proceeding
        try Task.checkCancellation()

        guard let tool = tools[name] else {
            throw AgentError.toolNotFound(name: name)
        }

        guard tool.isEnabled else {
            throw AgentError.toolNotFound(name: name)
        }

        // Normalize arguments (defaults + coercion) before guardrails/execution.
        let normalizedArguments = try tool.normalizeArguments(arguments)

        // Create a single GuardrailRunner instance for both input and output guardrails
        let runner = GuardrailRunner()
        let data = ToolGuardrailData(tool: tool, arguments: normalizedArguments, agent: agent, context: context)

        do {
            // Run input guardrails
            if !tool.inputGuardrails.isEmpty {
                _ = try await runner.runToolInputGuardrails(tool.inputGuardrails, data: data)
            }

            let result = try await tool.execute(arguments: normalizedArguments)

            // Run output guardrails
            if !tool.outputGuardrails.isEmpty {
                _ = try await runner.runToolOutputGuardrails(tool.outputGuardrails, data: data, output: result)
            }

            return result
        } catch {
            // Notify observer for any error (guardrail, execution, or otherwise)
            if let agent, let observer {
                await observer.onError(context: context, agent: agent, error: error)
            }

            // Re-throw original error or wrap it
            if let agentError = error as? AgentError {
                throw agentError
            } else if error is CancellationError {
                throw error
            } else if let guardrailError = error as? GuardrailError {
                throw guardrailError
            } else {
                throw AgentError.toolExecutionFailed(
                    toolName: name,
                    underlyingError: error.localizedDescription
                )
            }
        }
    }

    // MARK: Private

    private var tools: [String: any AnyJSONTool] = [:]
}
