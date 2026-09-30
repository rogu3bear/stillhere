import Foundation

/// Project manifest files the detector understands.
public enum ManifestKind: String, Sendable, Hashable, CaseIterable {
    case packageJSON = "package.json"
    case gemfile = "Gemfile"
    case pyproject = "pyproject.toml"
    case requirements = "requirements.txt"
    case managePy = "manage.py"
    case cargo = "Cargo.toml"
    case goMod = "go.mod"
    case denoJSON = "deno.json"
    case denoJSONC = "deno.jsonc"
}

/// What was learned from the manifests in one project directory.
public struct ManifestFacts: Sendable, Hashable {
    public var directory: URL
    public var kinds: Set<ManifestKind>
    /// Lowercased dependency names (package.json keys, Gemfile gems, Python requirement tokens).
    public var dependencies: Set<String>
    /// `scripts.dev` from package.json.
    public var devScript: String?

    public init(directory: URL, kinds: Set<ManifestKind> = [], dependencies: Set<String> = [], devScript: String? = nil) {
        self.directory = directory
        self.kinds = kinds
        self.dependencies = dependencies
        self.devScript = devScript
    }
}
