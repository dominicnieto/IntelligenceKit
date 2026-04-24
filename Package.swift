// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAISDK",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16)
    ],
    products: [
        // Main products matching upstream @ai-sdk architecture
        .library(name: "AISDKProvider", targets: ["AISDKProvider"]),
        .library(name: "AISDKProviderUtils", targets: ["AISDKProviderUtils"]),
        .library(name: "SwiftAISDK", targets: ["SwiftAISDK"]),
        .library(name: "OpenAIProvider", targets: ["OpenAIProvider"]),
        .library(name: "OpenAICompatibleProvider", targets: ["OpenAICompatibleProvider"]),
        .library(name: "AnthropicProvider", targets: ["AnthropicProvider"]),
        .library(name: "GatewayProvider", targets: ["GatewayProvider"]),
        .library(name: "GoogleProvider", targets: ["GoogleProvider"]),
        .library(name: "GoogleVertexProvider", targets: ["GoogleVertexProvider"]),
        .library(name: "MistralProvider", targets: ["MistralProvider"]),
        .library(name: "PerplexityProvider", targets: ["PerplexityProvider"]),
        .library(name: "ElevenLabsProvider", targets: ["ElevenLabsProvider"]),
        .library(name: "XAIProvider", targets: ["XAIProvider"]),
        .library(name: "VercelProvider", targets: ["VercelProvider"]),
        .library(name: "AISDKJSONSchema", targets: ["AISDKJSONSchema"]),
        .library(name: "AISDKZodAdapter", targets: ["AISDKZodAdapter"]),
        .executable(name: "playground", targets: ["SwiftAISDKPlayground"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/mattt/EventSource.git", from: "1.4.1")
    ],
    targets: [
        // AISDKProvider - Foundation types (matches @ai-sdk/provider)
        // Language model interfaces (V2/V3), provider errors, JSONValue, shared types
        .target(name: "AISDKProvider", dependencies: []),
        .testTarget(name: "AISDKProviderTests", dependencies: ["AISDKProvider"]),

        // AISDKProviderUtils - Provider utilities (matches @ai-sdk/provider-utils)
        // HTTP, JSON, schema, validation, retry, headers, ID generation, tools
        .target(
            name: "AISDKProviderUtils",
            dependencies: [
                "AISDKProvider",
                "AISDKZodAdapter",
                .product(name: "EventSource", package: "EventSource")
            ]
        ),
        .testTarget(name: "AISDKProviderUtilsTests", dependencies: ["AISDKProviderUtils", "AISDKZodAdapter"]),

        // Zod/ToJSONSchema adapters (public)
        .target(name: "AISDKZodAdapter", dependencies: ["AISDKProvider"]),

        // Provider targets
        .target(name: "OpenAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "OpenAICompatibleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "AnthropicProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "GatewayProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "GoogleProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "GoogleVertexProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "GoogleProvider"]),
        .target(name: "MistralProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "PerplexityProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "ElevenLabsProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils"]),
        .target(name: "XAIProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),
        .target(name: "VercelProvider", dependencies: ["AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),

        // JSON Schema generator (optional product)
        .target(
            name: "AISDKJSONSchema",
            dependencies: [
                "AISDKProviderUtils",
                "AISDKZodAdapter"
            ]
        ),
        .testTarget(name: "AISDKJSONSchemaTests", dependencies: ["AISDKJSONSchema", "AISDKProviderUtils"]),

        // SwiftAISDK - Main AI SDK (matches @ai-sdk/ai)
        // GenerateText, Registry, Middleware, Prompts, Tools, Telemetry
        .target(name: "SwiftAISDK", dependencies: ["AISDKProvider", "AISDKProviderUtils", "AISDKJSONSchema", "GatewayProvider"]),
        .testTarget(
            name: "SwiftAISDKTests",
            dependencies: ["SwiftAISDK", "OpenAIProvider", "OpenAICompatibleProvider"],
            resources: [.copy("OpenAI/Fixtures")]
        ),
        .testTarget(name: "OpenAICompatibleProviderTests", dependencies: ["OpenAICompatibleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "AnthropicProviderTests", dependencies: ["AnthropicProvider", "AISDKProvider", "AISDKProviderUtils"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GoogleProviderTests", dependencies: ["GoogleProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "GoogleVertexProviderTests", dependencies: ["GoogleVertexProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "GatewayProviderTests", dependencies: ["GatewayProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "MistralProviderTests", dependencies: ["MistralProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "PerplexityProviderTests", dependencies: ["PerplexityProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "ElevenLabsProviderTests", dependencies: ["ElevenLabsProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "XAIProviderTests", dependencies: ["XAIProvider", "AISDKProvider", "AISDKProviderUtils"]),
        .testTarget(name: "VercelProviderTests", dependencies: ["VercelProvider", "AISDKProvider", "AISDKProviderUtils", "OpenAICompatibleProvider"]),

        // SwiftAISDKPlayground - CLI executable for manual testing (Playground)
        .executableTarget(
            name: "SwiftAISDKPlayground",
            dependencies: [
                "SwiftAISDK",
                "AISDKProvider",
                "AISDKProviderUtils",
                "OpenAIProvider",
                "OpenAICompatibleProvider",
                "AnthropicProvider",
                "GatewayProvider",
                "GoogleProvider",
                "GoogleVertexProvider",
                "MistralProvider",
                "PerplexityProvider",
                "ElevenLabsProvider",
                "XAIProvider",
                "VercelProvider",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]
        )
    ],
    swiftLanguageModes: [.v6]
)
