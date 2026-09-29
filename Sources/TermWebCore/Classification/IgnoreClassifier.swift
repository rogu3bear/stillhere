import Foundation

/// Pure classification of a listener group as visible (nil) or hidden (with a reason).
///
/// Rule order, first match wins:
/// 0. interpreters (python*, node, bun, deno, ruby, php, java) skip rules 1-3 and 5
/// 1. executable under a system prefix -> `.system`
/// 2. cwd is `/` -> `.daemon`
/// 3. executable inside `*.app/Contents/` -> `.appHelper`
/// 4. process name in the name list -> `.ignoredName`
/// 5. port in the port list -> `.databasePort` (a database is never an interpreter
///    process, and dev servers bind whatever port they are given)
///
/// Rules 1-3 also decide `protection` (never signalled), always with every toggle on.
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
        let candidates = candidateNames(names, executablePath: executablePath)
        let isInterpreter = candidates.contains(where: isInterpreter)
        if !isInterpreter, let reason = structuralReason(executablePath: executablePath, cwd: cwd, rules: config) {
            return reason
        }
        for pattern in config.processNames {
            if let match = candidates.first(where: { matches($0, pattern: pattern) }) {
                return .ignoredName(match)
            }
        }
        if !isInterpreter, config.ports.contains(port) { return .databasePort(port) }
        return nil
    }

    /// Why a process must never be signalled: rules 1-3 with every toggle on. Turning a
    /// "hide" toggle off only changes what is listed, never what can be stopped.
    public static func protection(_ group: ListenerGroup, details: ProcessDetails?) -> HiddenReason? {
        protection(names: [group.rootCommand, details?.name].compactMap { $0 }, executablePath: details?.executablePath, cwd: details?.cwd)
    }

    public static func protection(names: [String], executablePath: String?, cwd: String?) -> HiddenReason? {
        guard !candidateNames(names, executablePath: executablePath).contains(where: isInterpreter) else { return nil }
        return structuralReason(executablePath: executablePath, cwd: cwd, rules: .defaults)
    }

    /// Rules 1-3, each applied only when `rules` turns it on.
    static func structuralReason(executablePath: String?, cwd: String?, rules: IgnoreConfiguration) -> HiddenReason? {
        if rules.hideSystemExecutables, let path = executablePath, systemPrefixes.contains(where: path.hasPrefix) {
            return .system
        }
        if rules.hideRootCwdDaemons, cwd == "/" { return .daemon }
        if rules.hideAppHelpers, let path = executablePath, path.contains(".app/Contents/") { return .appHelper }
        return nil
    }

    static func candidateNames(_ names: [String], executablePath: String?) -> [String] {
        let exeName = executablePath.map { ($0 as NSString).lastPathComponent }
        return (names + [exeName].compactMap { $0 }).filter { !$0.isEmpty }
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
