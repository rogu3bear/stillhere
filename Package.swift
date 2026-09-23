// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TermWeb",
    platforms: [.macOS(.v26)],
    products: [
        // The menu bar app's binary (Contents/MacOS/TermWeb in term-web.app).
        .executable(name: "TermWeb", targets: ["TermWebApp"]),
        // The command-line tool and MCP server, shipped inside the app bundle.
        .executable(name: "term-web", targets: ["TermWebCLI"]),
    ],
    targets: [
        // Detection library: nonisolated, Sendable value types, no UI imports.
        .target(name: "TermWebCore"),
        // UI target: MainActor by default.
        .executableTarget(
            name: "TermWebApp",
            dependencies: ["TermWebCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // CLI + MCP server: nonisolated, no SwiftUI.
        .executableTarget(
            name: "TermWebCLI",
            dependencies: ["TermWebCore"]
        ),
        .testTarget(
            name: "TermWebCoreTests",
            dependencies: ["TermWebCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TermWebCLITests",
            dependencies: ["TermWebCLI", "TermWebCore"]
        ),
        .testTarget(
            name: "TermWebAppTests",
            dependencies: ["TermWebApp", "TermWebCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
