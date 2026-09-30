import Foundation

/// Normalised view over a command line for token matching.
///
/// Each argument yields its lowercased basename (with `.js`/`.mjs`/`.cjs` stripped, so
/// `vite/bin/vite.js` reads as `vite`) and its first word (so title-rewritten argv such
/// as `next-server (v15.0.0)` or `puma 6.4 (tcp://...)` still match). Relative paths
/// are resolved against the process cwd.
public struct ArgvView: Sendable {
    public let argv: [String]
    public let resolvedPaths: [String]
    let tokens: [Set<String>]
    /// Process name and executable basename, lowercased.
    let names: Set<String>

    public init(argv: [String], name: String, executablePath: String?, cwd: String?) {
        self.argv = argv
        self.resolvedPaths = argv.map { Self.resolve($0, cwd: cwd) }
        self.tokens = argv.map(Self.tokens)
        let exeName = executablePath.map { ($0 as NSString).lastPathComponent }
        self.names = Set([name, exeName].compactMap { $0?.lowercased() }.filter { !$0.isEmpty })
    }

    /// Any argument, the process name or the executable name equals `token`.
    public func has(_ token: String) -> Bool {
        names.contains(token) || tokens.contains { $0.contains(token) }
    }

    public func hasPrefix(_ prefix: String) -> Bool {
        names.contains { $0.hasPrefix(prefix) } || tokens.contains { $0.contains { $0.hasPrefix(prefix) } }
    }

    /// `token` appears as an argument and one of `followers` appears later.
    public func has(_ token: String, followedBy followers: Set<String>) -> Bool {
        guard let index = tokens.firstIndex(where: { $0.contains(token) }) else { return false }
        return tokens[(index + 1)...].contains { !$0.isDisjoint(with: followers) }
    }

    /// `-m module` appears.
    public func hasModule(_ module: String) -> Bool {
        zip(argv, argv.dropFirst()).contains { $0 == "-m" && $1 == module }
    }

    public func hasArgument(_ argument: String) -> Bool { argv.contains(argument) }

    /// Some argument's resolved path ends with `suffix`.
    public func hasPathSuffix(_ suffix: String) -> Bool {
        resolvedPaths.contains { $0.hasSuffix(suffix) }
    }

    static func resolve(_ argument: String, cwd: String?) -> String {
        guard let cwd, !argument.hasPrefix("/"), !argument.hasPrefix("-"), argument.contains("/") else { return argument }
        return URL(fileURLWithPath: argument, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
            .standardizedFileURL.path
    }

    static func tokens(_ argument: String) -> Set<String> {
        let lower = argument.lowercased()
        var base = (lower as NSString).lastPathComponent
        for suffix in [".js", ".mjs", ".cjs"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let firstWord = lower.split(separator: " ", maxSplits: 1).first.map(String.init) ?? lower
        return Set([base, lower, firstWord].filter { !$0.isEmpty })
    }
}
