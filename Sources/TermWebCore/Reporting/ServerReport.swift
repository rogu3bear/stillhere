import Foundation

/// A server as the CLI and the MCP server report it. Deliberately omits argv and the
/// environment: command lines can carry tokens.
public struct ServerReport: Sendable, Hashable, Codable {
    public struct Project: Sendable, Hashable, Codable {
        public var name: String
        public var path: String
    }

    public struct Agent: Sendable, Hashable, Codable {
        public var kind: String
        public var name: String
        public var evidence: AgentContext.Evidence
        public var sessionID: String?
        public var launcherPID: Int32?
        public var launcherAlive: Bool?
        public var orphaned: Bool

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(evidence, forKey: .evidence)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(launcherPID, forKey: .launcherPID)
            try container.encode(launcherAlive, forKey: .launcherAlive)
            try container.encode(orphaned, forKey: .orphaned)
        }
    }

    public struct HTTP: Sendable, Hashable, Codable {
        public var status: Int?
        public var title: String?
        public var error: String?
        public var latencyMilliseconds: Int

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(title, forKey: .title)
            try container.encode(error, forKey: .error)
            try container.encode(latencyMilliseconds, forKey: .latencyMilliseconds)
        }
    }

    public var port: Int
    public var url: String
    public var pid: Int32
    public var process: String
    public var framework: String
    public var project: Project?
    public var git: GitContext?
    public var agent: Agent?
    public var http: HTTP?
    public var startedAt: Date?
    public var uptimeSeconds: Int?
    /// Why the row is hidden by the ignore rules, nil for visible servers.
    public var hidden: String?
    public var stoppable: Bool

    public init(entry: ServerEntry, probe: ProbeResult?, now: Date) {
        port = entry.port
        url = entry.url(for: probe).absoluteString
        pid = entry.rootPID
        process = entry.processName
        framework = (probe.map { FrameworkDetector.refine(entry.framework, with: $0) } ?? entry.framework).name
        project = entry.project.map { Project(name: $0.displayName, path: $0.fullPath) }
        git = entry.git
        agent = entry.agent.map {
            Agent(
                kind: $0.kind.slug,
                name: $0.kind.displayName,
                evidence: $0.evidence,
                sessionID: $0.sessionID,
                launcherPID: $0.launcherPID,
                launcherAlive: $0.launcherAlive,
                orphaned: $0.isOrphaned
            )
        }
        http = probe.map(Self.http)
        startedAt = entry.process?.startTime
        uptimeSeconds = entry.uptime(at: now).map { Int($0) }
        hidden = entry.hiddenReason?.label
        stoppable = entry.isStoppable
    }

    /// Every key is always present (null when unknown) so consumers can rely on the shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(port, forKey: .port)
        try container.encode(url, forKey: .url)
        try container.encode(pid, forKey: .pid)
        try container.encode(process, forKey: .process)
        try container.encode(framework, forKey: .framework)
        try container.encode(project, forKey: .project)
        try container.encode(git, forKey: .git)
        try container.encode(agent, forKey: .agent)
        try container.encode(http, forKey: .http)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(stoppable, forKey: .stoppable)
    }

    static func http(_ probe: ProbeResult) -> HTTP {
        let error: String? = switch probe.failure {
        case nil: nil
        case .refused?: "connection refused"
        case .timedOut?: "timed out"
        case .other(let code)?: "error \(code)"
        }
        return HTTP(
            status: probe.status,
            title: probe.title,
            error: error,
            latencyMilliseconds: Int((probe.latency.timeInterval * 1000).rounded())
        )
    }

    /// Stable JSON: sorted keys, ISO 8601 dates.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
