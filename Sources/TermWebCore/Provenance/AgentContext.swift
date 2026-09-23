import Foundation

/// The coding agent that started a server, and whether its session is still alive.
public struct AgentContext: Sendable, Hashable, Codable {
    public enum Kind: Sendable, Hashable, Codable {
        case claudeCode
        case codex
        /// Named by `AI_AGENT` or by an agent process found among the ancestors.
        case other(String)

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .other(let name): name
            }
        }

        /// Stable identifier for JSON output and filtering.
        public var slug: String {
            switch self {
            case .claudeCode: "claude-code"
            case .codex: "codex"
            case .other(let name): name.lowercased().replacingOccurrences(of: " ", with: "-")
            }
        }
    }

    /// How the attribution was made: environment markers survive the launcher exiting,
    /// ancestry only exists while the launcher is alive.
    public enum Evidence: String, Sendable, Hashable, Codable {
        case environment
        case ancestry
    }

    public var kind: Kind
    public var evidence: Evidence
    /// The agent session (Claude Code's `CLAUDE_CODE_SESSION_ID`), when the agent exposes one.
    public var sessionID: String?
    /// The agent process that launched the server, when known.
    public var launcherPID: Int32?
    /// nil when there is no launcher PID to check.
    public var launcherAlive: Bool?

    public init(
        kind: Kind,
        evidence: Evidence,
        sessionID: String? = nil,
        launcherPID: Int32? = nil,
        launcherAlive: Bool? = nil
    ) {
        self.kind = kind
        self.evidence = evidence
        self.sessionID = sessionID
        self.launcherPID = launcherPID
        self.launcherAlive = launcherAlive
    }

    /// Started by an agent whose session has ended: nothing will stop this server for you.
    /// Only claimed when the launcher PID is known and verifiably gone.
    public var isOrphaned: Bool { launcherAlive == false }
}

/// What identifies an agent-launched process.
public enum AgentMarkers {
    /// The only environment variables ever read from other processes. Values of every
    /// other variable are never decoded.
    public static let environmentKeys = [
        "CLAUDECODE",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_PID",
        "CODEX_SANDBOX",
        "AI_AGENT",
    ]

    static let environmentKeyBytes: [[UInt8]] = environmentKeys.map { Array($0.utf8) }

    /// Which agent a process is, from its name, executable path and (for Node-hosted CLIs)
    /// argv. Names alone are not enough: the native Claude Code binary lives at
    /// `~/.local/share/claude/versions/<version>`, so the kernel names it "2.1.280".
    public static func kind(name: String?, executablePath: String?, argv: [String] = []) -> AgentContext.Kind? {
        if let name, let kind = ancestorNames[name] { return kind }
        if let path = executablePath {
            if path.contains("/claude/versions/") { return .claudeCode }
            if let kind = ancestorNames[(path as NSString).lastPathComponent] { return kind }
        }
        // npm installs run under node: `node …/@anthropic-ai/claude-code/cli.js`, `node …/bin/codex`.
        if let script = argv.dropFirst().first {
            if script.contains("@anthropic-ai/claude-code") { return .claudeCode }
            if script.contains("@openai/codex") { return .codex }
        }
        return nil
    }

    /// Process names of agent CLIs, matched against ancestors while they are alive.
    public static let ancestorNames: [String: AgentContext.Kind] = [
        "claude": .claudeCode,
        "codex": .codex,
        "cursor-agent": .other("Cursor"),
        "gemini": .other("Gemini CLI"),
        "aider": .other("Aider"),
        "opencode": .other("opencode"),
        "amp": .other("Amp"),
    ]
}

/// Who is asking, for "servers I started" and the stop ownership rule: the calling
/// agent's session ID and its agent process. A server belongs to the caller when either
/// matches, so ownership survives a session ID change inside one Claude Code process
/// (`/clear`, resume).
public struct AgentOwner: Sendable, Hashable {
    public var sessionID: String?
    public var agentPID: Int32?

    public init(sessionID: String?, agentPID: Int32?) {
        self.sessionID = sessionID
        self.agentPID = agentPID
    }

    /// The owner described by Claude Code's markers in `environment`, if any.
    public init?(environment: [String: String]) {
        let session = environment["CLAUDE_CODE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }
        let pid = environment["CLAUDE_PID"].flatMap { Int32($0) }.flatMap { $0 > 1 ? $0 : nil }
        guard session != nil || pid != nil else { return nil }
        self.init(sessionID: session, agentPID: pid)
    }

    public func owns(_ agent: AgentContext?) -> Bool {
        guard let agent else { return false }
        if let sessionID, agent.sessionID == sessionID { return true }
        if let agentPID, agent.launcherPID == agentPID, agent.launcherAlive == true { return true }
        return false
    }
}
