import Foundation
import Testing
import TermWebCore
@testable import TermWebApp

@Suite struct ServerListModelTests {
    let temp = TemporaryDefaults()

    @Test func refreshSplitsVisibleAndHiddenAndCounts() async {
        let model = ServerListModel.make(FakeServerDetector(), defaults: temp)
        await model.refresh(.manual)

        #expect(model.servers.count == SampleServers.all.count)
        #expect(model.visibleServers.map(\.port) == [3000, 3001, 5000, 5173, 8000, 8001])
        #expect(model.hiddenServers.map(\.port) == [5432, 7000])
        #expect(model.visibleCount == 6)
        #expect(model.lastError == nil)
        #expect(model.lastRefreshed == SampleServers.referenceDate)
    }

    @Test func orphansAreCountedAmongVisibleServersOnly() async {
        let model = ServerListModel.make(FakeServerDetector(), defaults: temp)
        await model.refresh(.manual)
        #expect(model.orphanCount == 1) // SampleServers.next: its Claude Code session ended
    }

    @Test func refreshLoadsSessionsAndCountsCollisions() async {
        let model = ServerListModel(
            detector: FakeServerDetector(),
            sessionSource: FakeSessionSource(),
            settings: SettingsStore(defaults: temp.defaults),
            signaller: ProcessSignaller(system: InertSignalSystem()),
            clock: FixedNow(SampleServers.referenceDate)
        )
        await model.refresh(.manual)
        #expect(model.sessionOverview.sessions.map(\.pid) == [40_900, 42_000])
        #expect(model.collisionCount == 1)
        #expect(model.servers.filter(SampleSessions.claude.owns).map(\.port) == [5173])
    }

    @Test func showHiddenDoesNotChangeTheCount() async {
        let model = ServerListModel.make(FakeServerDetector(), defaults: temp)
        model.settings.showHiddenServers = true
        await model.refresh(.manual)
        #expect(model.visibleCount == 6)
    }

    @Test func concurrentRefreshesShareOneScan() async {
        let detector = FakeServerDetector(scenario: .init(delay: .milliseconds(100)))
        let model = ServerListModel.make(detector, defaults: temp)

        async let first: Void = model.refresh(.timer)
        async let second: Void = model.refresh(.menuOpened)
        async let third: Void = model.refresh(.manual)
        _ = await (first, second, third)

        #expect(detector.scanCount == 1)
        #expect(model.servers.count == SampleServers.all.count)
        #expect(!model.isRefreshing)
    }

    @Test func failedScanKeepsTheLastListAndReportsIt() async {
        let detector = FakeServerDetector()
        let model = ServerListModel.make(detector, defaults: temp)
        await model.refresh(.manual)

        var scenario = detector.scenario
        scenario.scanError = .commandFailed(executable: "/usr/sbin/lsof", status: 2)
        detector.scenario = scenario
        await model.refresh(.timer)

        #expect(model.servers.count == SampleServers.all.count)
        #expect(model.lastError == "lsof failed (exit 2).")

        scenario.scanError = nil
        detector.scenario = scenario
        await model.refresh(.timer)
        #expect(model.lastError == nil)
    }

    @Test func probesRunOnlyWhileThePanelIsOpenAndSkipHiddenRows() async {
        let detector = FakeServerDetector()
        let model = ServerListModel.make(detector, defaults: temp)

        await model.refresh(.timer)
        #expect(detector.probedPorts.isEmpty)

        model.isPanelOpen = true
        await model.refresh(.menuOpened)
        #expect(Set(detector.probedPorts) == Set(model.visibleServers.map(\.port)))
        #expect(model.probe(for: SampleServers.vite)?.title == "Shop — Vite + React")

        // Cached for one interval: a second open does not probe again.
        await model.refresh(.menuOpened)
        #expect(detector.probedPorts.count == model.visibleServers.count)
    }

    @Test func probingCanBeTurnedOff() async {
        let detector = FakeServerDetector()
        let model = ServerListModel.make(detector, defaults: temp)
        model.settings.probeHTTP = false
        model.isPanelOpen = true
        await model.refresh(.menuOpened)
        #expect(detector.probedPorts.isEmpty)
    }

    @Test func staleProbeIsDropped() async {
        let detector = FakeServerDetector()
        let model = ServerListModel.make(detector, defaults: temp)
        await model.refresh(.manual)

        // The probe was taken from an earlier process on the same port.
        var old = SampleServers.vite
        old.rootPID = 99_999
        model.apply(ProbeResult(host: ProbeHosts.ipv6, status: 500), for: old.probeKey)
        #expect(model.probe(for: SampleServers.vite) == nil)

        model.apply(ProbeResult(host: ProbeHosts.ipv6, status: 200), for: SampleServers.vite.probeKey)
        #expect(model.probe(for: SampleServers.vite)?.status == 200)

        // The process on the port changes: its old probe no longer applies.
        var scenario = detector.scenario
        scenario.entries = scenario.entries.map { $0.port == 5173 ? old : $0 }
        detector.scenario = scenario
        await model.refresh(.timer)
        #expect(model.probe(for: old) == nil)
        #expect(!model.probeRecords.values.contains { $0.key.port == 5173 })
    }

    @Test func headerRefinesARuntimeGuess() async {
        var node = SampleServers.vite
        node.framework = FrameworkGuess(name: "Node", source: .runtime)
        let detector = FakeServerDetector(scenario: .init(
            entries: [node],
            probes: [5173: ProbeResult(host: ProbeHosts.ipv6, status: 200, poweredBy: "Express")]
        ))
        let model = ServerListModel.make(detector, defaults: temp)
        model.isPanelOpen = true
        await model.refresh(.menuOpened)
        #expect(model.framework(for: node) == FrameworkGuess(name: "Express", source: .header))
    }

    @Test func scanUsesTheSettingsIgnoreRules() async {
        let detector = FakeServerDetector()
        let model = ServerListModel.make(detector, defaults: temp)
        model.settings.addProcessName("node")
        await model.refresh(.manual)
        #expect(detector.lastConfig?.processNames.contains("node") == true)
    }
}
