import Darwin
import Foundation
import Synchronization
import Testing
@testable import TermWebCore

final class FakeSignalSystem: SignalSystem {
    struct State {
        var lookup: ProcessLookup
        var alive = true
        var sendResult: Int32 = 0
        var sent: [Int32] = []
        var dieOnSignal = true
    }

    let state: Mutex<State>
    let ownPID: Int32 = 4_242
    let ownUID: UInt32 = 501

    init(start: Date, name: String = "node", uid: UInt32 = 501) {
        state = Mutex(State(lookup: .found(LiveProcess(startTime: start, name: name, uid: uid))))
    }

    init(lookup: ProcessLookup) { state = Mutex(State(lookup: lookup)) }

    var sent: [Int32] { state.withLock { $0.sent } }

    func send(_ signal: Int32, to pid: Int32) -> Int32 {
        state.withLock { state in
            state.sent.append(signal)
            if state.sendResult == 0, state.dieOnSignal { state.alive = false }
            return state.sendResult
        }
    }

    func isAlive(_ pid: Int32) -> Bool { state.withLock { $0.alive } }
    func lookup(_ pid: Int32) -> ProcessLookup { state.withLock { $0.lookup } }
}

@Suite struct ProcessSignallerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000.123456)

    func target(pid: Int32 = 500, name: String = "node", approximate: Bool = false) -> SignalTarget {
        SignalTarget(pid: pid, name: name, startTime: start, approximateStart: approximate)
    }

    @Test func startTimeMismatchSendsNothing() {
        let system = FakeSignalSystem(start: start.addingTimeInterval(5))
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(target()) == .pidReused)
        #expect(signaller.forceKill(target()) == .pidReused)
        #expect(system.sent.isEmpty)
    }

    @Test func nameMismatchSendsNothing() {
        let system = FakeSignalSystem(start: start, name: "sshd")
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.verify(target()) == .reused)
        #expect(signaller.terminate(target()) == .pidReused)
        #expect(signaller.forceKill(target()) == .pidReused)
        #expect(system.sent.isEmpty)
    }

    @Test func truncatedNamesStillMatch() {
        #expect(ProcessSignaller.namesMatch("Code Helper (Pl", "Code Helper (Plugin)"))
        #expect(ProcessSignaller.namesMatch("node", "node"))
        #expect(!ProcessSignaller.namesMatch("no", "node"))
        #expect(!ProcessSignaller.namesMatch("python3", "python3.13"))
    }

    @Test func terminateSendsOnlySIGTERM() {
        let system = FakeSignalSystem(start: start)
        #expect(ProcessSignaller(system: system).terminate(target()) == .sent)
        #expect(system.sent == [SIGTERM])
    }

    @Test func forceKillSendsSIGKILLOnlyWhenCalled() {
        let system = FakeSignalSystem(start: start)
        #expect(ProcessSignaller(system: system).forceKill(target()) == .sent)
        #expect(system.sent == [SIGKILL])
    }

    @Test func approximateStartTimeAllowsSecondResolution() {
        let system = FakeSignalSystem(start: start.addingTimeInterval(1.2))
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(target()) == .pidReused)
        #expect(signaller.terminate(target(approximate: true)) == .sent)
    }

    @Test func lookupAndSendErrorsAreReported() {
        #expect(ProcessSignaller(system: FakeSignalSystem(lookup: .notFound)).terminate(target()) == .notFound)
        #expect(ProcessSignaller(system: FakeSignalSystem(lookup: .denied)).terminate(target()) == .permissionDenied)
        let system = FakeSignalSystem(start: start)
        system.state.withLock { $0.sendResult = EPERM }
        #expect(ProcessSignaller(system: system).terminate(target()) == .permissionDenied)
        system.state.withLock { $0.sendResult = EINVAL }
        #expect(ProcessSignaller(system: system).terminate(target()) == .failed(errno: EINVAL))
    }

    @Test func refusesLaunchdInvalidAndOwnPIDs() {
        let system = FakeSignalSystem(start: start)
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(target(pid: 1)) == .refused(.protectedPID))
        #expect(signaller.forceKill(target(pid: 0)) == .refused(.protectedPID))
        #expect(signaller.forceKill(target(pid: -500)) == .refused(.protectedPID))
        #expect(signaller.terminate(target(pid: system.ownPID)) == .refused(.ownProcess))
        #expect(system.sent.isEmpty)
    }

    @Test func refusesOtherUsersProcesses() {
        let system = FakeSignalSystem(start: start, uid: 0)
        let signaller = ProcessSignaller(system: system)
        #expect(signaller.terminate(target()) == .refused(.otherUser))
        #expect(signaller.forceKill(target()) == .refused(.otherUser))
        #expect(system.sent.isEmpty)
    }

    @Test func waitForExitSucceedsOnceProcessAndPortAreGone() async {
        let system = FakeSignalSystem(start: start)
        let signaller = ProcessSignaller(system: system)
        _ = signaller.terminate(target())
        let stopped = await signaller.waitForExit(pid: 500, timeout: .milliseconds(200), pollInterval: .milliseconds(10)) { false }
        #expect(stopped)
    }

    @Test func waitForExitTimesOutWhenProcessIgnoresSIGTERM() async {
        let system = FakeSignalSystem(start: start)
        system.state.withLock { $0.dieOnSignal = false }
        let signaller = ProcessSignaller(system: system)
        _ = signaller.terminate(target())
        let stopped = await signaller.waitForExit(pid: 500, timeout: .milliseconds(100), pollInterval: .milliseconds(10)) { true }
        #expect(!stopped)
        #expect(system.sent == [SIGTERM])
    }

    @Test func waitForExitRequiresThePortToClose() async {
        let system = FakeSignalSystem(start: start)
        system.state.withLock { $0.alive = false }
        let stopped = await ProcessSignaller(system: system)
            .waitForExit(pid: 500, timeout: .milliseconds(80), pollInterval: .milliseconds(10)) { true }
        #expect(!stopped) // a worker still holds the port
    }

    @Test func darwinSystemSeesThisProcess() {
        let system = DarwinSignalSystem()
        let pid = getpid()
        #expect(system.isAlive(pid))
        #expect(system.ownPID == pid)
        #expect(system.ownUID == getuid())
        guard case .found(let live) = system.lookup(pid) else {
            Issue.record("no identity for own pid")
            return
        }
        #expect(live.startTime < Date())
        #expect(live.uid == getuid())
        #expect(!live.name.isEmpty)
        #expect(system.send(0, to: pid) == 0)
        // The signaller never targets its own process, even with a matching identity.
        let me = SignalTarget(pid: pid, name: live.name, startTime: live.startTime)
        #expect(ProcessSignaller(system: system).verify(me) == .refused(.ownProcess))
    }
}
