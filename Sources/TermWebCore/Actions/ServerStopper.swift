import Foundation

/// Stops one listed server without a UI: SIGTERM, wait for the process to exit and the
/// port to close, and SIGKILL only when asked and only the same verified process.
/// Shared by the CLI and the MCP server; the menu's `StopFlow` adds confirmation steps.
public struct ServerStopper: Sendable {
    public enum Result: Sendable, Hashable {
        case stopped(killed: Bool)
        /// SIGTERM was sent but the same process is still running (and `force` was off).
        case stillRunning
        case notStoppable(String)
        case failed(String)

        public var succeeded: Bool {
            if case .stopped = self { return true }
            return false
        }

        public var message: String {
            switch self {
            case .stopped(let killed): killed ? "stopped with SIGKILL" : "stopped"
            case .stillRunning: "still running after SIGTERM; retry with force to send SIGKILL"
            case .notStoppable(let reason), .failed(let reason): reason
            }
        }
    }

    private let signaller: ProcessSignaller
    private let detector: any ServerDetector
    private let config: IgnoreConfiguration
    private let exitTimeout: Duration

    public init(
        signaller: ProcessSignaller = ProcessSignaller(),
        detector: any ServerDetector = DefaultServerDetector(),
        config: IgnoreConfiguration = .defaults,
        exitTimeout: Duration = .seconds(3)
    ) {
        self.signaller = signaller
        self.detector = detector
        self.config = config
        self.exitTimeout = exitTimeout
    }

    public func stop(_ entry: ServerEntry, force: Bool) async -> Result {
        guard entry.isStoppable else {
            return .notStoppable("\(entry.processName) (PID \(entry.rootPID)) is a system, daemon or app-helper process; not stopped")
        }
        guard let target = SignalTarget(entry) else {
            return .notStoppable("start time of PID \(entry.rootPID) is unknown, so it can't be verified; not stopped")
        }
        if let failure = Self.failure(signaller.terminate(target), pid: target.pid) { return failure }
        if await waitForExit(target, port: entry.port) { return .stopped(killed: false) }
        guard signaller.verify(target) == .same else { return .stopped(killed: false) }
        guard force else { return .stillRunning }
        if let failure = Self.failure(signaller.forceKill(target), pid: target.pid) { return failure }
        return await waitForExit(target, port: entry.port)
            ? .stopped(killed: true)
            : .failed("PID \(target.pid) survived SIGKILL")
    }

    private func waitForExit(_ target: SignalTarget, port: Int) async -> Bool {
        let detector = detector
        let config = config
        return await signaller.waitForExit(pid: target.pid, timeout: exitTimeout) {
            guard let entries = try? await detector.scan(config: config) else { return true }
            return entries.contains { $0.port == port && $0.rootPID == target.pid }
        }
    }

    /// nil when the signal was sent (or the process had already exited).
    static func failure(_ outcome: SignalOutcome, pid: Int32) -> Result? {
        switch outcome {
        case .sent, .notFound: nil
        case .pidReused: .failed("PID \(pid) now belongs to a different process; nothing was sent")
        case .permissionDenied: .failed("permission denied signalling PID \(pid)")
        case .refused(.protectedPID): .notStoppable("PID \(pid) is protected; nothing was sent")
        case .refused(.ownProcess): .notStoppable("PID \(pid) is term-web itself; nothing was sent")
        case .refused(.otherUser): .notStoppable("PID \(pid) belongs to another user; nothing was sent")
        case .failed(let code): .failed("couldn't signal PID \(pid): \(String(cString: strerror(code)))")
        }
    }
}
