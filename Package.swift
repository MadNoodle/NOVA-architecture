// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "NOVA",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "NOVA", targets: ["NOVA"]),
    ],
    dependencies: [
        // Build-time only — not a runtime dependency of the NOVA library.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
    ],
    targets: [
        // Runtime library
        .target(
            name: "NOVA",
            dependencies: ["NOVAMacros"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Compiler plugin (macro implementation)
        .macro(
            name: "NOVAMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros",  package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // Runnable macOS demo: `swift run CounterAppDemo`
        .executableTarget(
            name: "CounterAppDemo",
            dependencies: ["NOVA"],
            path: "Examples/CounterApp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Tests — depends on NOVAMacros directly for assertMacroExpansion
        .testTarget(
            name: "NOVATests",
            dependencies: [
                "NOVA",
                "NOVAMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
