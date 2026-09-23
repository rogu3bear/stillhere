import Foundation
import Synchronization
import Testing
@testable import TermWebCore

/// Lists `entry` until the fake process has been signalled to death.
struct DyingDetector: ServerDetector {
    let entry: ServerEntry
    let system: FakeSignalSystem

    func scan(config: IgnoreConfiguration) async throws -> [ServerEntry] {
        system.isAlive(entry.rootPID) ? [entry] : []
    }

    func probe(_ entry: ServerEntry) async -> ProbeResult { ProbeResult(host: ProbeHosts.ipv4, status: 200) }
}

@Suite struct ServerStopperTests {
    let entry = SampleServers.vite
    var start: Date { entry.process!.startTime! }

    func stopper(_ system: FakeSignalSystem) -> ServerStopper {
        ServerStopper(
            signaller: ProcessSignaller(system: system),
            detector: DyingDetector(entry: entry, system: system),
            exitTimeout: .milliseconds(300)
        )
    }

    @Test func sigtermStopsAServer() async {
        let system = FakeSignalSystem(start: start)
        #expect(await stopper(system).stop(entry, force: false) == .stopped(killed: false))
        #expect(system.sent == [SIGTERM])
    }

    @Test func survivorIsNotKilledWithoutForce() async {
        let system = FakeSignalSystem(start: start)
        system.state.withLock { $0.dieOnSignal = false }
        #expect(await stopper(system).stop(entry, force: false) == .stillRunning)
        #expect(system.sent == [SIGTERM])
    }

    @Test func forceSendsSigkillToTheSameSurvivor() async {
        let system = FakeSignalSystem(start: start)
        system.state.withLock { $0.dieOnSignal = false }
        let result = await stopper(system).stop(entry, force: true)
        #expect(system.sent == [SIGTERM, SIGKILL])
        #expect(result == .failed("PID \(entry.rootPID) survived SIGKILL"))
    }

    @Test func protectedRowsAreNeverSignalled() async {
        let system = FakeSignalSystem(start: start)
        let result = await stopper(system).stop(SampleServers.controlCenter, force: true)
        guard case .notStoppable = result else { Issue.record("expected notStoppable, got \(result)"); return }
        #expect(system.sent.isEmpty)
    }

    @Test func reusedPIDIsNeverSignalled() async {
        let system = FakeSignalSystem(start: start.addingTimeInterval(60))
        guard case .failed = await stopper(system).stop(entry, force: true) else { Issue.record("expected failure"); return }
        #expect(system.sent.isEmpty)
    }
}

@Suite struct ServerQueryTests {
    let query = ServerQuery(detector: FakeServerDetector())

    @Test func hidesHiddenByDefault() async throws {
        let ports = try await query.entries().map(\.port)
        #expect(!ports.contains(5432))
        #expect(try await query.entries(.init(includeHidden: true)).map(\.port).contains(5432))
    }

    @Test func filtersBySessionOrphansAndPort() async throws {
        #expect(try await query.entries(.init(sessionID: "sample-session")).map(\.port) == [5173])
        #expect(try await query.entries(.init(orphansOnly: true)).map(\.port) == [3000])
        #expect(try await query.entries(.init(port: 8000)).map(\.port) == [8000])
    }

    @Test func reportsCarryProvenanceAndProbe() async throws {
        let reports = try await query.reports(.init(port: 3000), now: SampleServers.referenceDate)
        let next = try #require(reports.first)
        #expect(next.url == "http://localhost:3000/")
        #expect(next.git?.worktree == "blog-wt")
        #expect(next.agent?.kind == "claude-code")
        #expect(next.agent?.orphaned == true)
        #expect(next.http?.title == "My Blog")
        #expect(next.uptimeSeconds == 3_900)

        let json = String(decoding: try ServerReport.encoder().encode(reports), as: UTF8.self)
        #expect(json.contains("\"orphaned\" : true"))
        #expect(!json.contains("argv"))
    }
}
