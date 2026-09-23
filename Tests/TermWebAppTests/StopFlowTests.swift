import Darwin
import Foundation
import Testing
import TermWebCore
@testable import TermWebApp

@Suite struct StopFlowTests {
    let temp = TemporaryDefaults()
    let entry = SampleServers.flask

    private func setUp(fatal: Set<Int32>, start: Date? = nil) -> (ServerListModel, ScriptedSignalSystem, FakeServerDetector) {
        let detector = FakeServerDetector()
        let system = ScriptedSignalSystem(
            start: start ?? entry.process!.startTime!, fatalSignals: fatal, detector: detector, port: entry.port
        )
        return (ServerListModel.make(detector, defaults: temp, signalSystem: system), system, detector)
    }

    @Test func requestOnlyAsksForConfirmation() {
        let (model, system, _) = setUp(fatal: [SIGTERM])
        model.stopFlow.requestStop(entry)
        guard case .confirmTerminate(let target) = model.stopFlow.phase(for: entry.port) else {
            Issue.record("expected confirmation"); return
        }
        #expect(target.pid == entry.rootPID)
        #expect(system.sent.isEmpty)

        model.stopFlow.dismiss(port: entry.port)
        #expect(model.stopFlow.phase(for: entry.port) == nil)
        #expect(system.sent.isEmpty)
    }

    @Test func sigtermStopsTheServerAndRefreshes() async {
        let (model, system, detector) = setUp(fatal: [SIGTERM])
        await model.refresh(.manual)
        model.stopFlow.requestStop(entry)
        await model.stopFlow.confirmTerminate(port: entry.port)

        #expect(system.sent == [SIGTERM])
        #expect(model.stopFlow.phase(for: entry.port) == nil)
        #expect(!model.servers.contains { $0.port == entry.port })
        #expect(detector.scanCount >= 2)
    }

    @Test func survivingSigtermOffersSigkillWithoutSendingIt() async {
        let (model, system, _) = setUp(fatal: [SIGKILL])
        model.stopFlow.requestStop(entry)
        await model.stopFlow.confirmTerminate(port: entry.port)

        guard case .stillRunning(let target) = model.stopFlow.phase(for: entry.port) else {
            Issue.record("expected SIGKILL offer"); return
        }
        #expect(target.pid == entry.rootPID)
        #expect(system.sent == [SIGTERM])

        await model.stopFlow.confirmForceKill(port: entry.port)
        #expect(system.sent == [SIGTERM, SIGKILL])
        #expect(model.stopFlow.phase(for: entry.port) == nil)
    }

    @Test func forceKillNeedsTheStillRunningPhase() async {
        let (model, system, _) = setUp(fatal: [SIGKILL])
        model.stopFlow.requestStop(entry)
        await model.stopFlow.confirmForceKill(port: entry.port)
        #expect(system.sent.isEmpty)
    }

    @Test func reusedPIDAbortsWithoutSignalling() async {
        let (model, system, _) = setUp(fatal: [SIGTERM], start: entry.process!.startTime!.addingTimeInterval(60))
        model.stopFlow.requestStop(entry)
        await model.stopFlow.confirmTerminate(port: entry.port)

        #expect(system.sent.isEmpty)
        guard case .failed(let message) = model.stopFlow.phase(for: entry.port) else {
            Issue.record("expected failure"); return
        }
        #expect(message.contains("different process"))
    }

    @Test func unknownStartTimeIsNeverSignalled() {
        let (model, system, _) = setUp(fatal: [SIGTERM])
        var unknown = entry
        unknown.process?.startTime = nil
        model.stopFlow.requestStop(unknown)
        guard case .failed = model.stopFlow.phase(for: entry.port) else {
            Issue.record("expected failure"); return
        }
        #expect(system.sent.isEmpty)
    }
}
