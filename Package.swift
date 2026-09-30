// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillHere",
    platforms: [.macOS(.v26)],
    products: [
        // The menu bar app's binary (Contents/MacOS/StillHereApp in Still Here.app).
        .executable(name: "StillHereApp", targets: ["StillHereApp"]),
        // The command-line tool and MCP server, shipped inside the app bundle.
        .executable(name: "stillhere", targets: ["StillHereCLI"]),
    ],
    targets: [
        // Detection library: nonisolated, Sendable value types, no UI imports.
        .target(name: "StillHereCore"),
        // UI target: MainActor by default.
        .executableTarget(
            name: "StillHereApp",
            dependencies: ["StillHereCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // CLI + MCP server: nonisolated, no SwiftUI.
        .executableTarget(
            name: "StillHereCLI",
            dependencies: ["StillHereCore"]
        ),
        .testTarget(
            name: "StillHereCoreTests",
            dependencies: ["StillHereCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "StillHereCLITests",
            dependencies: ["StillHereCLI", "StillHereCore"]
        ),
        .testTarget(
            name: "StillHereAppTests",
            dependencies: ["StillHereApp", "StillHereCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
