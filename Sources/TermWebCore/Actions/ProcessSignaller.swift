import Foundation

/// Result of a start-time lookup.
public enum StartTimeLookup: Sendable, Hashable {
    case found(Date)
    case notFound
    case denied
}

/// The kernel operations the signaller needs; injectable so tests never signal anything.
public protocol SignalSystem: Sendable {
    /// Sends `signal` to `pid`; returns 0 on success or the `errno` value.
    func send(_ signal: Int32, to pid: Int32) -> Int32
    func isAlive(_ pid: Int32) -> Bool
    func startTime(of pid: Int32) -> StartTimeLookup
}

public enum SignalOutcome: Sendable, Hashable {
    case sent
    /// The PID now belongs to a different process (start time changed); nothing was sent.
    case pidReused
    case notFound
    case permissionDenied
    case failed(errno: Int32)
}

/// Sends SIGTERM or SIGKILL to one root PID (never a process group), after proving the
/// PID still names the process that was listed.
public struct ProcessSignaller: Sendable {
    private let system: any SignalSystem

    public init(system: any SignalSystem = DarwinSignalSystem()) {
        self.system = system
    }

    public func terminate(pid: Int32, expectedStart: Date, approximate: Bool = false) -> SignalOutcome {
        send(SIGTERM, to: pid, expectedStart: expectedStart, approximate: approximate)
    }

    /// SIGKILL. Only ever sent through this explicit call.
    public func forceKill(pid: Int32, expectedStart: Date, approximate: Bool = false) -> SignalOutcome {
        send(SIGKILL, to: pid, expectedStart: expectedStart, approximate: approximate)
    }

    /// Polls until the PID is gone and `isListening` reports the port closed, or the
    /// budget runs out. Returns true when the server stopped.
    public func waitForExit(
        pid: Int32,
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(250),
        isListening: @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if !system.isAlive(pid), await !isListening() { return true }
            guard clock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func send(_ signal: Int32, to pid: Int32, expectedStart: Date, approximate: Bool) -> SignalOutcome {
        guard pid > 1 else { return .permissionDenied }
        switch system.startTime(of: pid) {
        case .notFound:
            return .notFound
        case .denied:
            return .permissionDenied
        case .found(let actual):
            // `ps etime` has one-second resolution; libproc is exact to the microsecond.
            let tolerance: TimeInterval = approximate ? 2 : 0.001
            guard abs(actual.timeIntervalSince(expectedStart)) <= tolerance else { return .pidReused }
        }
        switch system.send(signal, to: pid) {
        case 0: return .sent
        case ESRCH: return .notFound
        case EPERM: return .permissionDenied
        case let code: return .failed(errno: code)
        }
    }
}
