import Darwin
import Foundation
import Observation
import TermWebCore

/// Per-process stop state machine:
/// confirmTerminate -> terminating -> (gone | stillRunning) -> killing -> (gone | stillRunning).
/// Phases are keyed by the row's process identity (port, PID, start time), so a phase never
/// carries over to a different process on the same port, and phases whose row disappeared
/// are pruned after each scan. Signals go to one verified PID (never a process group).
/// SIGKILL is only offered for the exact process that received SIGTERM, and only sent
/// after the user confirms it.
@Observable
final class StopFlow {
    /// The exact process a signal is aimed at.
    typealias Target = SignalTarget
    /// A row's process identity.
    typealias Key = ServerEntry.ProbeKey

    enum Phase: Hashable {
        case confirmTerminate(Target)
        case terminating(Target)
        /// The same process is still running after SIGTERM; offers SIGKILL for it.
        case stillRunning(Target)
        case killing(Target)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .terminating, .killing: true
            default: false
            }
        }
    }

    private(set) var phases: [Key: Phase] = [:]

    @ObservationIgnored private let detector: any ServerDetector
    @ObservationIgnored private let signaller: ProcessSignaller
    @ObservationIgnored private let configuration: () -> IgnoreConfiguration
    @ObservationIgnored private let exitTimeout: Duration
    @ObservationIgnored private let pollInterval: Duration
    /// Called after a server stopped (or its port changed hands), so the list can refresh.
    @ObservationIgnored var onStopped: (() async -> Void)?

    init(
        detector: any ServerDetector,
        signaller: ProcessSignaller,
        configuration: @escaping () -> IgnoreConfiguration,
        exitTimeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(250)
    ) {
        self.detector = detector
        self.signaller = signaller
        self.configuration = configuration
        self.exitTimeout = exitTimeout
        self.pollInterval = pollInterval
    }

    func phase(for entry: ServerEntry) -> Phase? { phases[entry.probeKey] }

    /// Step 1: ask for confirmation. Nothing is signalled yet.
    func requestStop(_ entry: ServerEntry) {
        let key = entry.probeKey
        guard phases[key]?.isBusy != true else { return }
        if !entry.isStoppable {
            phases[key] = .failed("\(entry.processName) is a system process; term-web won't stop it.")
        } else if let target = Target(entry) {
            phases[key] = .confirmTerminate(target)
        } else {
            phases[key] = .failed("Can't verify the process start time, so it won't be signalled.")
        }
    }

    /// Clears a confirmation, a SIGKILL offer or an error. Ignored while a signal is in progress.
    func dismiss(_ entry: ServerEntry) {
        let key = entry.probeKey
        guard phases[key]?.isBusy != true else { return }
        phases[key] = nil
    }

    /// Drops idle phases whose row is gone or now belongs to a different process.
    func prune(keeping entries: [ServerEntry]) {
        let live = Set(entries.map(\.probeKey))
        let kept = phases.filter { live.contains($0.key) || $0.value.isBusy }
        if kept.count != phases.count { phases = kept }
    }

    /// Step 2: SIGTERM, then wait for the process to exit and the port to close.
    func confirmTerminate(_ entry: ServerEntry) async {
        let key = entry.probeKey
        guard case .confirmTerminate(let target) = phases[key] else { return }
        phases[key] = .terminating(target)
        await signalAndWait(key: key, target: target, kill: false)
    }

    /// Step 3 (only after `stillRunning`): SIGKILL the same verified PID.
    func confirmForceKill(_ entry: ServerEntry) async {
        let key = entry.probeKey
        guard case .stillRunning(let target) = phases[key] else { return }
        phases[key] = .killing(target)
        await signalAndWait(key: key, target: target, kill: true)
    }

    private func signalAndWait(key: Key, target: Target, kill: Bool) async {
        let outcome = await Self.send(kill: kill, to: target, using: signaller)
        switch outcome {
        case .sent, .notFound:
            break // notFound: it already exited; confirm the port closed below.
        case .pidReused:
            phases[key] = .failed("PID \(target.pid) now belongs to a different process. Nothing was sent; refresh.")
            return
        case .permissionDenied:
            phases[key] = .failed("Permission denied signalling PID \(target.pid).")
            return
        case .refused(let reason):
            phases[key] = .failed(Self.describe(reason, pid: target.pid))
            return
        case .failed(let code):
            phases[key] = .failed("Couldn't signal PID \(target.pid): \(String(cString: strerror(code))).")
            return
        }

        let isListening = Self.listeningCheck(port: key.port, detector: detector, config: configuration())
        let stopped = await signaller.waitForExit(
            pid: target.pid, timeout: exitTimeout, pollInterval: pollInterval, isListening: isListening
        )
        if !stopped, await Self.verify(target, using: signaller) == .same {
            phases[key] = .stillRunning(target)
            return
        }
        // Stopped, or the original process exited and something else now holds the port:
        // that is a different server, never a SIGKILL candidate. Refresh to show it.
        phases[key] = nil
        await onStopped?()
    }

    static func describe(_ reason: SignalRefusal, pid: Int32) -> String {
        switch reason {
        case .protectedPID: "PID \(pid) is a protected system process; nothing was sent."
        case .ownProcess: "PID \(pid) is term-web itself; nothing was sent."
        case .otherUser: "PID \(pid) belongs to another user; nothing was sent."
        }
    }

    /// `kill(2)` and the libproc identity check run off the main actor.
    @concurrent
    nonisolated private static func send(kill: Bool, to target: Target, using signaller: ProcessSignaller) async -> SignalOutcome {
        kill ? signaller.forceKill(target) : signaller.terminate(target)
    }

    @concurrent
    nonisolated private static func verify(_ target: Target, using signaller: ProcessSignaller) async -> TargetVerification {
        signaller.verify(target)
    }

    /// A fresh listener scan, off the main actor. A failed scan counts as still listening.
    nonisolated private static func listeningCheck(
        port: Int, detector: any ServerDetector, config: IgnoreConfiguration
    ) -> @Sendable () async -> Bool {
        { @concurrent in
            guard let entries = try? await detector.scan(config: config) else { return true }
            return entries.contains { $0.port == port }
        }
    }
}
