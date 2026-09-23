import Darwin
import Foundation
import Synchronization
import Testing
@testable import TermWebCore

final class FakeSignalSystem: SignalSystem {
    struct State {
        var start: StartTimeLookup
        var alive = true
        var sendResult: Int32 = 0
        var sent: [Int32] = []
        var dieOnSignal = true
    }

    let state: Mutex<State>

    init(start: StartTimeLookup) { state = Mutex(State(start: start)) }

    var sent: [Int32] { state.withLock { $0.sent } }

    func send(_ signal: Int32, to pid: Int32) -> Int32 {
        state.withLock { state in
            state.sent.append(signal)
            if state.sendResult == 0, state.dieOnSignal { state.alive = false }
            return state.sendResult
        }
    }

    func isAlive(_ pid: Int32) -> Bool { state.withLock { $0.alive } }
    func startTime(of pid: Int32) -> StartTimeLookup { state.withLock { $0.start } }
}

@Suite struct ProcessSignallerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000.123456)

    @Test func startTimeMismatchSendsNothing() {
        let system = FakeSignalSystem(start: .found(start.addingTimeInterval(5)))
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(pid: 500, expectedStart: start) == .pidReused)
        #expect(signaller.forceKill(pid: 500, expectedStart: start) == .pidReused)
        #expect(system.sent.isEmpty)
    }

    @Test func terminateSendsOnlySIGTERM() {
        let system = FakeSignalSystem(start: .found(start))
        #expect(ProcessSignaller(system: system).terminate(pid: 500, expectedStart: start) == .sent)
        #expect(system.sent == [SIGTERM])
    }

    @Test func forceKillSendsSIGKILLOnlyWhenCalled() {
        let system = FakeSignalSystem(start: .found(start))
        #expect(ProcessSignaller(system: system).forceKill(pid: 500, expectedStart: start) == .sent)
        #expect(system.sent == [SIGKILL])
    }

    @Test func approximateStartTimeAllowsSecondResolution() {
        let system = FakeSignalSystem(start: .found(start.addingTimeInterval(1.2)))
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(pid: 500, expectedStart: start) == .pidReused)
        #expect(signaller.terminate(pid: 500, expectedStart: start, approximate: true) == .sent)
    }

    @Test func lookupAndSendErrorsAreReported() {
        #expect(ProcessSignaller(system: FakeSignalSystem(start: .notFound)).terminate(pid: 500, expectedStart: start) == .notFound)
        #expect(ProcessSignaller(system: FakeSignalSystem(start: .denied)).terminate(pid: 500, expectedStart: start) == .permissionDenied)
        let system = FakeSignalSystem(start: .found(start))
        system.state.withLock { $0.sendResult = EPERM }
        #expect(ProcessSignaller(system: system).terminate(pid: 500, expectedStart: start) == .permissionDenied)
        system.state.withLock { $0.sendResult = EINVAL }
        #expect(ProcessSignaller(system: system).terminate(pid: 500, expectedStart: start) == .failed(errno: EINVAL))
    }

    @Test func refusesLaunchdAndInvalidPIDs() {
        let system = FakeSignalSystem(start: .found(start))
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(pid: 1, expectedStart: start) == .permissionDenied)
        #expect(signaller.forceKill(pid: 0, expectedStart: start) == .permissionDenied)
        #expect(system.sent.isEmpty)
    }

    @Test func waitForExitSucceedsOnceProcessAndPortAreGone() async {
        let system = FakeSignalSystem(start: .found(start))
        let signaller = ProcessSignaller(system: system)
        _ = signaller.terminate(pid: 500, expectedStart: start)
        let stopped = await signaller.waitForExit(pid: 500, timeout: .milliseconds(200), pollInterval: .milliseconds(10)) { false }
        #expect(stopped)
    }

    @Test func waitForExitTimesOutWhenProcessIgnoresSIGTERM() async {
        let system = FakeSignalSystem(start: .found(start))
        system.state.withLock { $0.dieOnSignal = false }
        let signaller = ProcessSignaller(system: system)
        _ = signaller.terminate(pid: 500, expectedStart: start)
        let stopped = await signaller.waitForExit(pid: 500, timeout: .milliseconds(100), pollInterval: .milliseconds(10)) { true }
        #expect(!stopped)
        #expect(system.sent == [SIGTERM])
    }

    @Test func waitForExitRequiresThePortToClose() async {
        let system = FakeSignalSystem(start: .found(start))
        system.state.withLock { $0.alive = false }
        let stopped = await ProcessSignaller(system: system)
            .waitForExit(pid: 500, timeout: .milliseconds(80), pollInterval: .milliseconds(10)) { true }
        #expect(!stopped) // a worker still holds the port
    }

    @Test func darwinSystemSeesThisProcess() {
        let system = DarwinSignalSystem()
        let pid = getpid()
        #expect(system.isAlive(pid))
        guard case .found(let date) = system.startTime(of: pid) else {
            Issue.record("no start time for own pid")
            return
        }
        #expect(date < Date())
        #expect(system.send(0, to: pid) == 0)
    }
}
