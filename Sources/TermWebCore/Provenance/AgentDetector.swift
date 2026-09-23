import Foundation

/// Attributes a server to the coding agent that started it. Pure: the caller supplies the
/// allowlisted environment, the ancestor chain and a way to look up the launcher.
public enum AgentDetector {
    /// Environment first (it survives the launcher exiting and double-forked servers),
    /// then the nearest agent process among live ancestors.
    public static func detect(
        environment: [String: String],
        ancestors: [ProcessDetails],
        serverStart: Date?,
        lookup: (Int32) -> ProcessDetails?
    ) -> AgentContext? {
        if var context = fromEnvironment(environment) {
            if let pid = context.launcherPID {
                context.launcherAlive = isAlive(pid, startedBy: serverStart, lookup: lookup)
            } else if let ancestor = ancestors.first(where: { kind(ofProcessNamed: $0.name) == context.kind }) {
                context.launcherPID = ancestor.pid
                context.launcherAlive = true
            }
            return context
        }
        for ancestor in ancestors {
            if let kind = kind(ofProcessNamed: ancestor.name) {
                return AgentContext(kind: kind, evidence: .ancestry, launcherPID: ancestor.pid, launcherAlive: true)
            }
        }
        return nil
    }

    static func fromEnvironment(_ environment: [String: String]) -> AgentContext? {
        if environment["CLAUDECODE"] == "1" {
            return AgentContext(
                kind: .claudeCode,
                evidence: .environment,
                sessionID: environment["CLAUDE_CODE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 },
                launcherPID: environment["CLAUDE_PID"].flatMap { Int32($0) }.flatMap { $0 > 1 ? $0 : nil }
            )
        }
        if environment["CODEX_SANDBOX"] != nil {
            return AgentContext(kind: .codex, evidence: .environment)
        }
        if let marker = environment["AI_AGENT"], let name = agentName(fromMarker: marker) {
            return AgentContext(kind: name, evidence: .environment)
        }
        return nil
    }

    /// `AI_AGENT` values look like `claude-code_2-1-280_agent`: the name is before the first `_`.
    static func agentName(fromMarker marker: String) -> AgentContext.Kind? {
        let name = marker.split(separator: "_", maxSplits: 1).first.map(String.init) ?? ""
        switch name {
        case "": return nil
        case "claude-code": return .claudeCode
        case "codex": return .codex
        default: return .other(name)
        }
    }

    static func kind(ofProcessNamed name: String?) -> AgentContext.Kind? {
        guard let name else { return nil }
        return AgentMarkers.ancestorNames[name]
    }

    /// The launcher is alive when its PID exists and was started no later than the server;
    /// a later start time means the PID was reused by an unrelated process.
    static func isAlive(_ pid: Int32, startedBy serverStart: Date?, lookup: (Int32) -> ProcessDetails?) -> Bool {
        guard let launcher = lookup(pid) else { return false }
        guard let serverStart, let launcherStart = launcher.startTime else { return true }
        return launcherStart <= serverStart
    }
}
