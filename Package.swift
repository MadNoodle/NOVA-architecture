// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SECA",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SECA", targets: ["SECA"]),
    ],
    dependencies: [
        // Build-time only — not a runtime dependency of the SECA library.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
    ],
    targets: [
        // Runtime library
        .target(
            name: "SECA",
            dependencies: ["SECAMacros"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Compiler plugin (macro implementation)
        .macro(
            name: "SECAMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros",  package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // Runnable macOS demo: `swift run CounterAppDemo`
        .executableTarget(
            name: "CounterAppDemo",
            dependencies: ["SECA"],
            path: "Examples/CounterApp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Tests — depends on SECAMacros directly for assertMacroExpansion
        .testTarget(
            name: "SECATests",
            dependencies: [
                "SECA",
                "SECAMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
