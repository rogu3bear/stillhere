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
