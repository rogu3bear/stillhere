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
    }

    public struct HTTP: Sendable, Hashable, Codable {
        public var status: Int?
        public var title: String?
        public var error: String?
        public var latencyMilliseconds: Int
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
