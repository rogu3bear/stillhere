import Foundation

/// One row: every listener on a port, merged across IPv4/IPv6 and forked workers.
public struct ServerEntry: Sendable, Hashable, Identifiable {
    /// Identity key for probes: a result is stale unless all three still match.
    public struct ProbeKey: Sendable, Hashable {
        public var port: Int
        public var pid: Int32
        public var startTime: Date?
    }

    /// Stable row identity across refreshes.
    public var id: Int { port }
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

    public init(
        port: Int,
        rootPID: Int32,
        workerPIDs: [Int32] = [],
        bindings: [Binding],
        command: String,
        process: ProcessDetails? = nil,
        project: ProjectLocation? = nil,
        framework: FrameworkGuess,
        hiddenReason: HiddenReason? = nil
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
    }

    public var isHidden: Bool { hiddenReason != nil }

    /// The URL shown, copied and opened. `localhost` resolves both families.
    public var displayURL: URL { URL(string: "http://localhost:\(port)/")! }

    public var processName: String { process?.name ?? command }

    public var probeKey: ProbeKey {
        ProbeKey(port: port, pid: rootPID, startTime: process?.startTime)
    }

    public func uptime(at now: Date) -> TimeInterval? {
        guard let start = process?.startTime else { return nil }
        return max(0, now.timeIntervalSince(start))
    }
}
