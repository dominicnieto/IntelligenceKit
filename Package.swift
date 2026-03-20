// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"
let useLocalDeps = ProcessInfo.processInfo.environment["AISTACK_USE_LOCAL_DEPS"] == "1"

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmHive", targets: ["SwarmHive"]),
    .library(name: "SwarmMembrane", targets: ["SwarmMembrane"]),
    .library(name: "SwarmMCP", targets: ["SwarmMCP"]),
]

if includeDemo {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
    packageProducts.append(.executable(name: "SwarmMCPServerDemo", targets: ["SwarmMCPServerDemo"]))
}

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"601.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.2"),
]

if useLocalDeps {
    packageDependencies += [
        .package(path: packageRoot.appendingPathComponent("../Wax").path),
        .package(
            path: packageRoot.appendingPathComponent("../Conduit").path,
            traits: [
                .trait(name: "OpenAI"),
                .trait(name: "OpenRouter"),
                .trait(name: "Anthropic"),
            ]
        ),
        .package(path: packageRoot.appendingPathComponent("../Membrane").path),
        .package(path: packageRoot.appendingPathComponent("../Hive").path),
    ]
} else {
    packageDependencies += [
        .package(url: "https://github.com/christopherkarani/Wax.git", exact: "0.1.19"),
        .package(
            url: "https://github.com/christopherkarani/Conduit",
            exact: "0.3.10",
            traits: [
                .trait(name: "OpenAI"),
                .trait(name: "OpenRouter"),
                .trait(name: "Anthropic"),
            ]
        ),
        .package(url: "https://github.com/christopherkarani/Membrane", exact: "0.1.2"),
        .package(url: "https://github.com/christopherkarani/Hive", exact: "0.1.8"),
    ]
}

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
    .product(name: "SwiftSoup", package: "SwiftSoup"),
    .product(name: "Wax", package: "Wax"),
    .product(name: "Conduit", package: "Conduit"),
    .product(name: "HiveCore", package: "Hive"),
    .product(name: "Membrane", package: "Membrane", condition: .when(traits: ["membrane"])),
    .product(name: "MembraneHive", package: "Membrane", condition: .when(traits: ["membrane"]))
]

if useLocalDeps {
    swarmDependencies.append(.product(name: "ConduitAdvanced", package: "Conduit"))
}

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .define("SWARM_HIVE", .when(traits: ["hive"])),
    .define("SWARM_MEMBRANE", .when(traits: ["membrane"]))
]

var packageTargets: [Target] = [
    // MARK: - Macro Implementation (Compiler Plugin)
    .macro(
        name: "SwarmMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Main Library
    .target(
        name: "Swarm",
        dependencies: swarmDependencies,
        exclude: [
            "HiveSwarm",
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmHive",
        dependencies: [
            "Swarm",
            .product(name: "HiveCore", package: "Hive"),
        ],
        path: "Sources/Swarm/HiveSwarm",
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMembrane",
        dependencies: [
            "Swarm",
        ],
        path: "Sources/SwarmMembrane",
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMCP",
        dependencies: [
            "Swarm",
            .product(name: "MCP", package: "swift-sdk"),
        ],
        swiftSettings: swarmSwiftSettings
    ),

    // MARK: - Tests
    .testTarget(
        name: "SwarmTests",
        dependencies: {
            var dependencies: [Target.Dependency] = [
                "Swarm",
                "SwarmHive",
                "SwarmMCP",
                .product(name: "Conduit", package: "Conduit"),
                .product(name: "Membrane", package: "Membrane", condition: .when(traits: ["membrane"])),
                .product(name: "MembraneCore", package: "Membrane", condition: .when(traits: ["membrane"])),
            ]
            if useLocalDeps {
                dependencies.append(.product(name: "ConduitAdvanced", package: "Conduit"))
            }
            return dependencies
        }(),
        resources: [
            .copy("Guardrails/INTEGRATION_TEST_SUMMARY.md"),
            .copy("Guardrails/QUICK_REFERENCE.md")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "HiveSwarmTests",
        dependencies: [
            "Swarm",
            "SwarmHive",
            .product(name: "HiveCore", package: "Hive")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "SwarmMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    )
]

if includeDemo {
    packageTargets.append(
        .executableTarget(
            name: "SwarmDemo",
            dependencies: ["Swarm"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )

    packageTargets.append(
        .executableTarget(
            name: "SwarmMCPServerDemo",
            dependencies: [
                "Swarm",
                "SwarmMCP",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )
}

let package = Package(
    name: "Swarm",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
    ],
    products: packageProducts,
    traits: [
        .trait(
            name: "hive",
            description: "Enable Hive-backed workflow and runtime integration features."
        ),
        .trait(
            name: "membrane",
            description: "Enable Membrane-based planning and tool output transformations."
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
