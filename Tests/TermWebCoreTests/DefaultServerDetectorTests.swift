import Foundation
import Synchronization
import Testing
@testable import TermWebCore

struct StubListenerSource: ListenerSource {
    var records: [ListenerRecord]
    func listeners() async throws -> [ListenerRecord] { records }
}

struct StubInspector: ProcessInspector {
    var table: [Int32: ProcessDetails]
    func details(for pids: [Int32]) async -> [Int32: ProcessDetails] {
        table.filter { pids.contains($0.key) }
    }
}

final class RecordingProber: HTTPProber {
    private let calls = Mutex<[(Int, [Binding])]>([])
    var recorded: [(Int, [Binding])] { calls.withLock { $0 } }

    func probe(port: Int, bindings: [Binding]) async -> ProbeResult {
        calls.withLock { $0.append((port, bindings)) }
        return ProbeResult(host: ProbeHosts.hosts(for: bindings)[0], status: 200, title: "Port \(port)")
    }
}

@Suite struct DefaultServerDetectorTests {
    @Test func scanEndToEndWithFakes() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let shop = home.appending(path: "Projects/shop")
        try FileManager.default.createDirectory(at: shop.appending(path: "src"), withIntermediateDirectories: true)
        try #"{"devDependencies":{"vite":"6"}}"#.write(to: shop.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let site = home.appending(path: "Downloads/site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)

        let records = LsofListenParser.parse(try Fixture.text("lsof-listen-dev.txt"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let inspector = StubInspector(table: [
            70_001: ProcessDetails(pid: 70_001, ppid: 69_990, name: "node", startTime: start,
                                   executablePath: "/usr/local/bin/node", argv: ["node", "server.mjs"],
                                   cwd: shop.appending(path: "src").path),
            70_030: ProcessDetails(pid: 70_030, name: "Python", startTime: start,
                                   executablePath: "/opt/homebrew/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python",
                                   argv: ["Python", "-m", "http.server", "8765"], cwd: site.path),
            70_050: ProcessDetails(pid: 70_050, name: "postgres", executablePath: "/opt/homebrew/bin/postgres", cwd: "/opt/homebrew/var/postgresql@17"),
            70_040: ProcessDetails(pid: 70_040, name: "Python", argv: ["python3", "-m", "flask", "run"], cwd: "/Users/nobody/api"),
        ])
        let prober = RecordingProber()
        let detector = DefaultServerDetector(
            listenerSource: StubListenerSource(records: records),
            inspector: inspector,
            prober: prober,
            homeDirectory: home.path
        )

        let entries = try await detector.scan(config: .defaults)
        #expect(entries.map(\.port) == [5000, 5173, 5432, 8765, 8767, 8769])

        let vite = try #require(entries.first { $0.port == 5173 })
        #expect(vite.framework == FrameworkGuess(name: "Vite", source: .manifest))
        #expect(vite.project?.displayName == "shop")
        #expect(vite.project?.fullPath == shop.path)
        #expect(vite.project?.cwd.lastPathComponent == "src")
        #expect(vite.displayURL.absoluteString == "http://localhost:5173/")
        #expect(vite.hiddenReason == nil)
        #expect(vite.uptime(at: start.addingTimeInterval(65)) == 65)

        let httpServer = try #require(entries.first { $0.port == 8765 })
        #expect(httpServer.framework.name == "Python http.server")
        #expect(httpServer.hiddenReason == nil)
        #expect(httpServer.project?.displayName == "site")

        let flask = try #require(entries.first { $0.port == 5000 })
        #expect(flask.framework.name == "Flask")
        #expect(flask.hiddenReason == nil)

        let postgres = try #require(entries.first { $0.port == 5432 })
        #expect(postgres.hiddenReason == .ignoredName("postgres"))
        #expect(postgres.project?.fullPath == "/opt/homebrew/var/postgresql@17") // hidden rows skip manifest lookup
        #expect(postgres.bindings.count == 2)

        let forked = try #require(entries.first { $0.port == 8769 })
        #expect(forked.rootPID == 70_020)
        #expect(forked.workerPIDs == [70_021])
        #expect(forked.process == nil) // no details: shown with the lsof name only
        #expect(forked.framework == FrameworkGuess(name: "Python", source: .runtime))

        let probe = await detector.probe(vite)
        #expect(probe.host == "[::1]")
        #expect(prober.recorded.map(\.0) == [5173])
    }

    @Test func turningOffHideRulesNeverMakesSystemListenersStoppable() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        func record(_ pid: Int32, _ command: String, _ port: Int) -> ListenerRecord {
            ListenerRecord(pid: pid, ppid: 1, command: command, family: .ipv4, bindAddress: "127.0.0.1", port: port)
        }
        let detector = DefaultServerDetector(
            listenerSource: StubListenerSource(records: [
                record(650, "ControlCenter", 7000), record(919, "HttpToUsbBridge", 50_000),
                record(18_204, "star-mlxd", 8702), record(21_749, "bun", 4173),
            ]),
            inspector: StubInspector(table: [
                650: ProcessDetails(pid: 650, name: "ControlCenter", executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", cwd: "/"),
                919: ProcessDetails(pid: 919, name: "HttpToUsbBridge", executablePath: "/Library/Printers/Brother/HttpToUsbBridge.app/Contents/MacOS/HttpToUsbBridge", cwd: "/"),
                18_204: ProcessDetails(pid: 18_204, name: "star-mlxd", executablePath: home.path + "/Applications/STAR.app/Contents/Resources/bin/star-mlxd", cwd: home.path),
                21_749: ProcessDetails(pid: 21_749, name: "bun", executablePath: home.path + "/.bun/bin/bun", cwd: home.path),
            ]),
            prober: RecordingProber(),
            homeDirectory: home.path
        )

        let shown = try await detector.scan(config: .none)
        #expect(shown.allSatisfy { !$0.isHidden })
        #expect(shown.filter(\.isStoppable).map(\.port) == [4173])
        #expect(shown.first { $0.port == 7000 }?.protection == .system)
        #expect(shown.first { $0.port == 50_000 }?.protection == .daemon)
        #expect(shown.first { $0.port == 8702 }?.protection == .appHelper)

        let hidden = try await detector.scan(config: .defaults)
        #expect(hidden.filter(\.isHidden).map(\.port) == [7000, 8702, 50_000])
        #expect(hidden.filter(\.isStoppable).map(\.port) == [4173])
    }

    @Test func scanErrorsPropagate() async {
        struct Failing: ListenerSource {
            func listeners() async throws -> [ListenerRecord] { throw DetectionError.commandFailed(executable: "lsof", status: 9) }
        }
        let detector = DefaultServerDetector(listenerSource: Failing(), inspector: StubInspector(table: [:]), prober: RecordingProber())
        await #expect(throws: DetectionError.self) { try await detector.scan(config: .defaults) }
    }

    @Test func fakeDetectorServesScenario() async throws {
        let fake = FakeServerDetector()
        let entries = try await fake.scan(config: .defaults)
        #expect(entries == SampleServers.all)
        #expect(entries.map(\.port) == entries.map(\.port).sorted())
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(entries.filter(\.isHidden).count == 2)
        #expect(await fake.probe(SampleServers.vite).title == "Shop — Vite + React")
        #expect(fake.scanCount == 1)
        #expect(fake.probedPorts == [5173])

        fake.scenario.scanError = .commandFailed(executable: "lsof", status: 1)
        await #expect(throws: DetectionError.self) { try await fake.scan(config: .none) }
        #expect(fake.lastConfig == IgnoreConfiguration.none)
    }
}
