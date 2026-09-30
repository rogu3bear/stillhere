import Foundation

/// Everything the detector looks at for one process.
public struct FrameworkSignals: Sendable {
    public var argv: [String]
    public var name: String
    public var executablePath: String?
    public var cwd: String?
    public var manifest: ManifestFacts?

    public init(argv: [String], name: String, executablePath: String? = nil, cwd: String? = nil, manifest: ManifestFacts? = nil) {
        self.argv = argv
        self.name = name
        self.executablePath = executablePath
        self.cwd = cwd
        self.manifest = manifest
    }
}

/// Pure framework guessing: argv, then manifest, then runtime. Headers refine a
/// runtime-only guess after the probe.
public enum FrameworkDetector {
    public static func guess(_ signals: FrameworkSignals) -> FrameworkGuess {
        let view = ArgvView(argv: signals.argv, name: signals.name, executablePath: signals.executablePath, cwd: signals.cwd)
        for rule in FrameworkRules.argv {
            if let name = rule(view, signals.manifest) { return FrameworkGuess(name: name, source: .argv) }
        }
        if let manifest = signals.manifest, let name = frameworkFromManifest(manifest) {
            return FrameworkGuess(name: name, source: .manifest)
        }
        if let runtime = runtime(view, executablePath: signals.executablePath) {
            return FrameworkGuess(name: runtime, source: .runtime)
        }
        if let manifest = signals.manifest, let language = languageFromManifest(manifest) {
            return FrameworkGuess(name: language, source: .manifest)
        }
        let fallback = signals.name.isEmpty
            ? signals.executablePath.map { ($0 as NSString).lastPathComponent } ?? "Unknown"
            : signals.name
        return FrameworkGuess(name: fallback, source: .runtime)
    }

    /// Replaces a runtime-only guess when response headers name the server.
    public static func refine(_ guess: FrameworkGuess, with probe: ProbeResult) -> FrameworkGuess {
        guard guess.source == .runtime else { return guess }
        if let value = probe.poweredBy?.lowercased(),
           let match = FrameworkRules.poweredBy.first(where: { value.hasPrefix($0.prefix) }) {
            return FrameworkGuess(name: match.name, source: .header)
        }
        if let value = probe.serverHeader?.lowercased(),
           let match = FrameworkRules.serverHeader.first(where: { value.hasPrefix($0.prefix) }) {
            return FrameworkGuess(name: match.name, source: .header)
        }
        return guess
    }

    static func frameworkFromManifest(_ manifest: ManifestFacts) -> String? {
        let dependencies = manifest.dependencies
        func contains(_ dependency: String) -> Bool {
            dependency.hasSuffix("*")
                ? dependencies.contains { $0.hasPrefix(dependency.dropLast()) }
                : dependencies.contains(dependency)
        }
        if manifest.kinds.contains(.packageJSON) {
            if let match = FrameworkRules.packageDependencies.first(where: { contains($0.dependency) }) { return match.name }
            if let script = manifest.devScript?.lowercased(),
               let match = FrameworkRules.packageDependencies.first(where: { script.contains($0.scriptWord) }) {
                return match.name
            }
        }
        if manifest.kinds.contains(.gemfile),
           let match = FrameworkRules.rubyDependencies.first(where: { contains($0.dependency) }) {
            return match.name
        }
        if !manifest.kinds.isDisjoint(with: [.pyproject, .requirements]),
           let match = FrameworkRules.pythonDependencies.first(where: { contains($0.dependency) }) {
            return match.name
        }
        if manifest.kinds.contains(.managePy) { return "Django" }
        return nil
    }

    static func languageFromManifest(_ manifest: ManifestFacts) -> String? {
        if manifest.kinds.contains(.cargo) { return "Rust" }
        if manifest.kinds.contains(.goMod) { return "Go" }
        if !manifest.kinds.isDisjoint(with: [.denoJSON, .denoJSONC]) { return "Deno" }
        return nil
    }

    static func runtime(_ view: ArgvView, executablePath: String?) -> String? {
        let names = view.names.union(view.argv.prefix(1).map { ($0.lowercased() as NSString).lastPathComponent })
        if names.contains("bun") { return "Bun" }
        if names.contains("deno") { return "Deno" }
        if names.contains("node") { return "Node" }
        if names.contains(where: { $0.hasPrefix("python") }) { return "Python" }
        if names.contains("ruby") { return "Ruby" }
        if names.contains("java") { return "Java" }
        if names.contains(where: { $0.hasPrefix("php") }) { return "PHP" }
        let paths = [executablePath].compactMap { $0 } + view.resolvedPaths.prefix(1)
        if paths.contains(where: { $0.contains("/target/debug/") || $0.contains("/target/release/") }) {
            return "Rust (cargo)"
        }
        return nil
    }
}
