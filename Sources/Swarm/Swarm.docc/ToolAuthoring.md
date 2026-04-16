# Tool Authoring

Four ways to define a tool, in order of preference.

## The `@Tool` macro (recommended)

Annotate a struct with `@Tool`. The macro synthesizes `name`, `description`,
`parameters`, and the ``AnyJSONTool`` adapter from `@Parameter`-annotated
properties.

```swift
@Tool("Gets current weather for a city")
struct GetWeather {
    @Parameter("City name, e.g. 'San Francisco'")
    var city: String

    @Parameter("Temperature units", default: "celsius")
    var units: String = "celsius"

    func execute() async throws -> String {
        "72°F and sunny in \(city)"
    }
}
```

`@Parameter` supports defaults and enumerated string choices:

```swift
@Parameter("Output format", oneOf: ["json", "xml", "plain"])
var format: String

@Parameter("Include forecast", default: false)
var forecast: Bool = false
```

## Manual `Tool` conformance

When the macro is too restrictive (custom input types, computed parameters,
cross-field validation), conform to ``Tool`` directly:

```swift
struct CalculateMortgage: Tool {
    struct Input: Codable, Sendable {
        let principal: Double
        let rate: Double
        let years: Int
    }

    struct Output: Codable, Sendable {
        let monthlyPayment: Double
        let totalInterest: Double
    }

    let name = "calculate_mortgage"
    let description = "Calculate monthly mortgage payments"

    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "principal", description: "Loan amount", type: .double),
            ToolParameter(name: "rate", description: "Annual interest rate", type: .double),
            ToolParameter(name: "years", description: "Loan term in years", type: .int)
        ]
    }

    func execute(_ input: Input) async throws -> Output {
        let r = input.rate / 12 / 100
        let n = Double(input.years * 12)
        let payment = input.principal * (r * pow(1 + r, n)) / (pow(1 + r, n) - 1)
        return Output(
            monthlyPayment: payment,
            totalInterest: payment * n - input.principal
        )
    }
}
```

The framework bridges `Tool` to ``AnyJSONTool`` via `AnyJSONToolAdapter` so the
typed tool can still live in a ``ToolRegistry`` next to dynamic ones.

## `FunctionTool` closures

For quick one-offs that don't warrant a dedicated struct, use a closure:

```swift
let echo = FunctionTool(name: "echo", description: "Echoes input") { args in
    let message = try args.require("message", as: String.self)
    return .string("Echo: \(message)")
}
```

With an explicit parameter schema:

```swift
let search = FunctionTool(
    name: "search",
    description: "Search the web",
    parameters: [
        ToolParameter(name: "query", description: "Search query", type: .string),
        ToolParameter(
            name: "limit",
            description: "Max results",
            type: .int,
            isRequired: false,
            defaultValue: .int(10)
        )
    ]
) { args in
    let query = try args.require("query", as: String.self)
    let limit = args.int("limit", default: 10)
    // perform search…
    return .array([.string("Result 1"), .string("Result 2")])
}
```

``ToolArguments`` supports `require`, `optional`, `string(_:default:)`, and
`int(_:default:)` for extracting typed values from the raw argument dictionary.

## Dynamic `AnyJSONTool` conformance

Drop all the way down to ``AnyJSONTool`` only when you need behavior that
doesn't fit the typed ``Tool`` shape — for example, when the parameter schema
is computed at runtime from a config file:

```swift
struct RuntimeConfiguredTool: AnyJSONTool {
    var name: String { "dynamic_search" }
    var description: String { "Search across sources configured at runtime" }
    var parameters: [ToolParameter] {
        // Built from configuration, not known at compile time
        ToolRegistryConfig.current.searchParameters
    }
    var inputGuardrails: [any ToolInputGuardrail] { [] }
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let query = try requiredString("query", from: arguments)
        let source = optionalString("source", from: arguments) ?? "web"
        return .string("\(source) results for \(query)")
    }
}
```

## Parameter schemas

``ToolParameter/ParameterType`` covers the full JSON-schema shape space:

```swift
// Simple
ToolParameter(name: "city", description: "City", type: .string)
ToolParameter(name: "limit", description: "Max rows", type: .int,
              isRequired: false, defaultValue: .int(10))

// Array
ToolParameter(name: "tags", description: "Filter tags",
              type: .array(elementType: .string))

// Nested object
ToolParameter(
    name: "address",
    description: "Mailing address",
    type: .object(properties: [
        ToolParameter(name: "street", description: "Street", type: .string),
        ToolParameter(name: "city", description: "City", type: .string),
        ToolParameter(name: "zip", description: "ZIP", type: .string)
    ])
)

// String enum
ToolParameter(name: "units", description: "Units",
              type: .oneOf(["celsius", "fahrenheit"]),
              isRequired: false,
              defaultValue: .string("celsius"))
```

## Registration

Pass tools directly to an agent:

```swift
let agent = try Agent(
    tools: [GetWeather(), CalculateMortgage(), echo],
    instructions: "..."
)
```

Or build a ``ToolRegistry`` and execute by name:

```swift
let registry = try ToolRegistry(tools: [echo, search])
let result = try await registry.execute(
    toolNamed: "echo",
    arguments: ["message": .string("hello")]
)
```

``ToolRegistry`` is an actor — call from `async` context. It handles the full
execution lifecycle: cancellation check, lookup, enabled-check, argument
normalization, input guardrails, execute, output guardrails.

## When to pick which

| Tool type | Pick when |
|---|---|
| `@Tool` macro | Default. 80%+ of tools. |
| Manual `Tool` | Custom `Input` struct, non-trivial parameter construction, validation across fields. |
| `FunctionTool` | One-off, one-file, doesn't need its own type. |
| `AnyJSONTool` directly | Parameters computed at runtime; integrating with a foreign schema system. |

## Errors

Tool execution throws ``AgentError/toolExecutionFailed(toolName:underlyingError:)``
when your `execute` raises a non-agent error. Argument validation throws
``AgentError/invalidToolArguments(toolName:reason:)``. Missing/disabled tools
surface as ``AgentError/toolNotFound(name:)``. See <doc:ErrorHandling>.
