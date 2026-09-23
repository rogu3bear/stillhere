// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TermWeb",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "term-web", targets: ["TermWebApp"]),
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
        .testTarget(
            name: "TermWebCoreTests",
            dependencies: ["TermWebCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
