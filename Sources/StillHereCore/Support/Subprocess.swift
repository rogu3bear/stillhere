import Foundation
import Synchronization

/// Captured result of a finished command.
public struct CommandOutput: Sendable, Hashable {
    public var status: Int32
    public var stdout: Data

    public init(status: Int32, stdout: Data) {
        self.status = status
        self.stdout = stdout
    }

    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

public enum SubprocessError: Error, Sendable, Equatable {
    case launchFailed(executable: String, message: String)
    case timedOut(executable: String)
    case cancelled(executable: String)
}

/// Runs an external command. Injected so parsers' callers can be tested with canned output.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> CommandOutput
}

/// `Process` + `Pipe` runner. Never blocks the calling thread: stdout is drained on a
/// background queue (so a full pipe cannot deadlock) and completion resumes a continuation.
/// The process is terminated on timeout or task cancellation.
public struct Subprocess: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: Duration = .seconds(5)) async throws -> CommandOutput {
        let job = Job(executable: executable, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            job.stop(reason: .cancelled)
        }
    }
}

/// Owns one `Process`. Mutable state sits behind a `Mutex`; the `Process` itself is only
/// touched through calls Foundation documents as safe from any thread (`run` once,
/// `terminate`, `isRunning`, and `terminationStatus` after exit), hence `@unchecked`.
private final class Job: @unchecked Sendable {
    enum StopReason: Sendable { case timedOut, cancelled }

    private struct State {
        var stopReason: StopReason?
        var started = false
        var finished = false
    }

    private let executable: String
    private let process: Process
    private let pipe = Pipe()
    private let state = Mutex(State())
    private let output = Mutex(Data())

    init(executable: String, arguments: [String]) {
        self.executable = executable
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
        process.standardOutput = pipe
    }

    func start(timeout: Duration, continuation: CheckedContinuation<CommandOutput, any Error>) {
        if let reason = state.withLock({ $0.stopReason }) {
            continuation.resume(throwing: error(for: reason))
            return
        }
        let group = DispatchGroup()
        group.enter() // termination
        group.enter() // stdout drained
        process.terminationHandler = { [self] _ in
            state.withLock { $0.finished = true }
            group.leave()
        }
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: SubprocessError.launchFailed(executable: executable, message: "\(error)"))
            return
        }
        // A stop requested between the check above and run() must still take effect.
        let pendingStop = state.withLock { state -> Bool in
            state.started = true
            return state.stopReason != nil
        }
        if pendingStop { process.terminate() }

        let reader = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [self] in
            let data = (try? reader.readToEnd()) ?? Data()
            output.withLock { $0 = data }
            group.leave()
        }
        let timer = DispatchWorkItem { [weak self] in self?.stop(reason: .timedOut) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout.timeInterval, execute: timer)

        group.notify(queue: .global(qos: .utility)) { [self] in
            timer.cancel()
            process.terminationHandler = nil // breaks the Job -> Process -> handler cycle
            if let reason = state.withLock({ $0.stopReason }) {
                continuation.resume(throwing: error(for: reason))
            } else {
                continuation.resume(returning: CommandOutput(
                    status: process.terminationStatus,
                    stdout: output.withLock { $0 }
                ))
            }
        }
    }

    func stop(reason: StopReason) {
        let shouldTerminate = state.withLock { state -> Bool in
            guard !state.finished else { return false }
            if state.stopReason == nil { state.stopReason = reason }
            return state.started
        }
        if shouldTerminate, process.isRunning { process.terminate() }
    }

    private func error(for reason: StopReason) -> SubprocessError {
        switch reason {
        case .timedOut: .timedOut(executable: executable)
        case .cancelled: .cancelled(executable: executable)
        }
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`.
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
