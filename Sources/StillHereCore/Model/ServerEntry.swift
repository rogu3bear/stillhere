import Foundation

/// One row: every listener on a port, merged across IPv4/IPv6 and forked workers.
public struct ServerEntry: Sendable, Hashable, Identifiable {
    /// Identity key for probes: a result is stale unless all three still match.
    public struct ProbeKey: Sendable, Hashable {
        public var port: Int
        public var pid: Int32
        public var startTime: Date?

        /// The owning row's `ServerEntry.id`.
        public var entryID: String { "\(port)/\(pid)" }
    }

    /// Stable, unique row identity across refreshes: one row per process tree on a port.
    public var id: String { probeKey.entryID }
    public var port: Int
    public var rootPID: Int32
    public var workerPIDs: [Int32]
    public var bindings: [Binding]
    /// Process name from the listener source.
    public var command: String
    public var process: ProcessDetails?
    public var project: ProjectLocation?
    public var framework: FrameworkGuess
    public var hiddenReason: HiddenReason?
    /// Why stillhere never signals this process (system, daemon or app helper), whether or not
    /// the ignore rules hide it.
    public var protection: HiddenReason?
    /// The checkout the server runs from (visible rows only).
    public var git: GitContext?
    /// The coding agent that started it (visible rows only).
    public var agent: AgentContext?

    public init(
        port: Int,
        rootPID: Int32,
        workerPIDs: [Int32] = [],
        bindings: [Binding],
        command: String,
        process: ProcessDetails? = nil,
        project: ProjectLocation? = nil,
        framework: FrameworkGuess,
        hiddenReason: HiddenReason? = nil,
        protection: HiddenReason? = nil,
        git: GitContext? = nil,
        agent: AgentContext? = nil
    ) {
        self.port = port
        self.rootPID = rootPID
        self.workerPIDs = workerPIDs
        self.bindings = bindings
        self.command = command
        self.process = process
        self.project = project
        self.framework = framework
        self.hiddenReason = hiddenReason
        self.protection = protection
        self.git = git
        self.agent = agent
    }

    public var isHidden: Bool { hiddenReason != nil }

    /// False for system, daemon and app-helper listeners: the app never offers to stop those,
    /// even when a "hide" rule for them is turned off.
    public var isStoppable: Bool { protection == nil && hiddenReason?.isProtected != true }

    /// The URL shown, copied and opened, before a probe has told us the scheme.
    /// `localhost` resolves both families.
    public var displayURL: URL { url(scheme: "http") }

    public func url(scheme: String) -> URL { URL(string: "\(scheme)://localhost:\(port)/")! }

    /// The URL to show once a probe is known: HTTPS when the server only speaks TLS.
    public func url(for probe: ProbeResult?) -> URL { url(scheme: probe?.scheme ?? "http") }

    public var processName: String { process?.name ?? command }

    public var probeKey: ProbeKey {
        ProbeKey(port: port, pid: rootPID, startTime: process?.startTime)
    }

    public func uptime(at now: Date) -> TimeInterval? {
        guard let start = process?.startTime else { return nil }
        return max(0, now.timeIntervalSince(start))
    }
}
