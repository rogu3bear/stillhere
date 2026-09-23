import Darwin
import Foundation
import Observation
import TermWebCore

/// Per-port stop state machine:
/// confirmTerminate -> terminating -> (gone | stillRunning) -> killing -> (gone | stillRunning).
/// Signals go to one verified PID (never a process group). SIGKILL is only sent after the
/// user confirms it in the `stillRunning` phase.
@Observable
final class StopFlow {
    /// The exact process a signal is aimed at.
    struct Target: Hashable {
        var pid: Int32
        var name: String
        var startTime: Date
        var approximateStart: Bool

        init?(_ entry: ServerEntry) {
            guard let start = entry.process?.startTime else { return nil }
            pid = entry.rootPID
            name = entry.processName
            startTime = start
            approximateStart = entry.process?.startTimeIsApproximate ?? false
        }
    }

    enum Phase: Hashable {
        case confirmTerminate(Target)
        case terminating(Target)
        /// Still listening after SIGTERM (or SIGKILL of a parent); offers SIGKILL.
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

    private(set) var phases: [Int: Phase] = [:]

    @ObservationIgnored private let detector: any ServerDetector
    @ObservationIgnored private let signaller: ProcessSignaller
    @ObservationIgnored private let configuration: () -> IgnoreConfiguration
    @ObservationIgnored private let exitTimeout: Duration
    @ObservationIgnored private let pollInterval: Duration
    /// Called after a server stopped, so the list can refresh.
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

    func phase(for port: Int) -> Phase? { phases[port] }

    /// Step 1: ask for confirmation. Nothing is signalled yet.
    func requestStop(_ entry: ServerEntry) {
        guard phases[entry.port]?.isBusy != true else { return }
        if let target = Target(entry) {
            phases[entry.port] = .confirmTerminate(target)
        } else {
            phases[entry.port] = .failed("Can't verify the process start time, so it won't be signalled.")
        }
    }

    /// Clears a confirmation, a SIGKILL offer or an error. Ignored while a signal is in progress.
    func dismiss(port: Int) {
        guard phases[port]?.isBusy != true else { return }
        phases[port] = nil
    }

    /// Step 2: SIGTERM, then wait for the process to exit and the port to close.
    func confirmTerminate(port: Int) async {
        guard case .confirmTerminate(let target) = phases[port] else { return }
        phases[port] = .terminating(target)
        await signalAndWait(port: port, target: target, kill: false)
    }

    /// Step 3 (only after `stillRunning`): SIGKILL the listed PID.
    func confirmForceKill(port: Int) async {
        guard case .stillRunning(let target) = phases[port] else { return }
        phases[port] = .killing(target)
        await signalAndWait(port: port, target: target, kill: true)
    }

    private func signalAndWait(port: Int, target: Target, kill: Bool) async {
        let outcome = await Self.send(kill: kill, to: target, using: signaller)
        switch outcome {
        case .sent, .notFound:
            break // notFound: it already exited; confirm the port closed below.
        case .pidReused:
            phases[port] = .failed("PID \(target.pid) now belongs to a different process. Nothing was sent; refresh.")
            return
        case .permissionDenied:
            phases[port] = .failed("Permission denied signalling PID \(target.pid).")
            return
        case .failed(let code):
            phases[port] = .failed("Couldn't signal PID \(target.pid): \(String(cString: strerror(code))).")
            return
        }

        let isListening = Self.listeningCheck(port: port, detector: detector, config: configuration())
        let stopped = await signaller.waitForExit(
            pid: target.pid, timeout: exitTimeout, pollInterval: pollInterval, isListening: isListening
        )
        if stopped {
            phases[port] = nil
            await onStopped?()
            return
        }
        phases[port] = .stillRunning(await holder(of: port) ?? target)
    }

    /// Whoever holds the port now: the original PID, or a worker that outlived it
    /// (reparented, so it is the new root in a fresh scan).
    private func holder(of port: Int) async -> Target? {
        let entries = try? await detector.scan(config: configuration())
        return entries?.first { $0.port == port }.flatMap(Target.init)
    }

    /// `kill(2)` and the libproc start-time check run off the main actor.
    @concurrent
    nonisolated private static func send(kill: Bool, to target: Target, using signaller: ProcessSignaller) async -> SignalOutcome {
        kill
            ? signaller.forceKill(pid: target.pid, expectedStart: target.startTime, approximate: target.approximateStart)
            : signaller.terminate(pid: target.pid, expectedStart: target.startTime, approximate: target.approximateStart)
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
