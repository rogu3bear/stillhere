import Foundation

/// Pure classification of a listener group as visible (nil) or hidden (with a reason).
///
/// Rule order, first match wins:
/// 0. interpreters (python*, node, bun, deno, ruby, php, java) skip rules 1-3
/// 1. executable under a system prefix -> `.system`
/// 2. cwd is `/` -> `.daemon`
/// 3. executable inside `*.app/Contents/` -> `.appHelper`
/// 4. process name in the name list -> `.ignoredName`
/// 5. port in the port list -> `.databasePort`
public enum IgnoreClassifier {
    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"]
    static let interpreters: Set<String> = ["node", "bun", "deno", "ruby", "php", "java"]

    public static func classify(_ group: ListenerGroup, details: ProcessDetails?, config: IgnoreConfiguration) -> HiddenReason? {
        classify(
            names: [group.rootCommand, details?.name].compactMap { $0 },
            executablePath: details?.executablePath,
            cwd: details?.cwd,
            port: group.port,
            config: config
        )
    }

    public static func classify(names: [String], executablePath: String?, cwd: String?, port: Int, config: IgnoreConfiguration) -> HiddenReason? {
        let exeName = executablePath.map { ($0 as NSString).lastPathComponent }
        let candidates = (names + [exeName].compactMap { $0 }).filter { !$0.isEmpty }

        if !candidates.contains(where: isInterpreter) {
            if config.hideSystemExecutables, let path = executablePath,
               systemPrefixes.contains(where: path.hasPrefix) {
                return .system
            }
            if config.hideRootCwdDaemons, cwd == "/" { return .daemon }
            if config.hideAppHelpers, let path = executablePath, path.contains(".app/Contents/") {
                return .appHelper
            }
        }
        for pattern in config.processNames {
            if let match = candidates.first(where: { matches($0, pattern: pattern) }) {
                return .ignoredName(match)
            }
        }
        if config.ports.contains(port) { return .databasePort(port) }
        return nil
    }

    static func isInterpreter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("python") || interpreters.contains(lower)
    }

    /// Case-insensitive exact match; a trailing `*` matches any suffix.
    public static func matches(_ name: String, pattern: String) -> Bool {
        let pattern = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        let name = name.lowercased()
        guard !pattern.isEmpty else { return false }
        if pattern.hasSuffix("*") { return name.hasPrefix(pattern.dropLast()) }
        return name == pattern
    }
}
