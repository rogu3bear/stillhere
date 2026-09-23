import Testing
@testable import TermWebCore

@Suite struct IgnoreClassifierTests {
    let config = IgnoreConfiguration.defaults

    func classify(_ name: String, exe: String?, cwd: String?, port: Int, config: IgnoreConfiguration = .defaults) -> HiddenReason? {
        IgnoreClassifier.classify(names: [name], executablePath: exe, cwd: cwd, port: port, config: config)
    }

    @Test func controlCenterIsHidden() {
        #expect(classify("ControlCenter", exe: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", cwd: "/", port: 5000) == .system)
        // Without libproc details it is still hidden, by name.
        #expect(classify("ControlCenter", exe: nil, cwd: nil, port: 7000) == .ignoredName("ControlCenter"))
        let noStructural = IgnoreConfiguration(hideSystemExecutables: false, hideRootCwdDaemons: false, hideAppHelpers: false)
        #expect(classify("ControlCenter", exe: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", cwd: "/", port: 5000, config: noStructural) == .ignoredName("ControlCenter"))
    }

    @Test func rootCwdDaemonIsHidden() {
        #expect(classify("HttpToUsbBridge", exe: "/Library/Printers/Brother/HttpToUsbBridge.app/Contents/MacOS/HttpToUsbBridge", cwd: "/", port: 50_000) == .daemon)
        #expect(classify("rapportd", exe: "/usr/libexec/rapportd", cwd: "/", port: 49_152) == .system)
    }

    @Test func homebrewPythonAppWithProjectCwdIsVisible() {
        let exe = "/opt/homebrew/Cellar/python@3.13/3.13.1/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"
        #expect(classify("Python", exe: exe, cwd: "/Users/dev/site", port: 8765) == nil)
        // The interpreter allowlist also beats the cwd rule.
        #expect(classify("node", exe: "/usr/local/bin/node", cwd: "/", port: 3000) == nil)
    }

    @Test func flaskOnPort5000IsVisible() {
        #expect(classify("python3.13", exe: "/opt/homebrew/bin/python3.13", cwd: "/Users/dev/api", port: 5000) == nil)
    }

    @Test func databasesAreHidden() {
        #expect(classify("postgres", exe: "/opt/homebrew/opt/postgresql@17/bin/postgres", cwd: "/opt/homebrew/var", port: 5432) == .ignoredName("postgres"))
        #expect(classify("docker-proxy", exe: "/usr/local/bin/docker-proxy", cwd: "/tmp", port: 5432) == .databasePort(5432))
    }

    @Test func appHelperIsHidden() {
        #expect(classify("star-mlxd", exe: "/Users/dev/Applications/STAR.app/Contents/Resources/STARRuntime/bin/star-mlxd", cwd: "/Users/dev/proj", port: 8702) == .appHelper)
    }

    @Test func bunDevServerIsVisible() {
        #expect(classify("bun", exe: "/Users/dev/.bun/bin/bun", cwd: "/Users/dev/token-bar/site", port: 4173) == nil)
    }

    @Test func wildcardAndCaseInsensitiveNames() {
        #expect(IgnoreClassifier.matches("Code Helper (Plugin)", pattern: "Code Helper*"))
        #expect(IgnoreClassifier.matches("controlcenter", pattern: "ControlCenter"))
        #expect(!IgnoreClassifier.matches("ControlCenterX", pattern: "ControlCenter"))
        #expect(!IgnoreClassifier.matches("anything", pattern: "  "))
        #expect(classify("Adobe Desktop Service", exe: nil, cwd: "/tmp", port: 15_292) == .ignoredName("Adobe Desktop Service"))
    }

    @Test func defaultsNeverHideAirPlayPortsOrPort9000ByPort() {
        #expect(!config.ports.contains(5000))
        #expect(!config.ports.contains(7000))
        #expect(!config.ports.contains(9000))
    }

    @Test func machineFixtureVisibility() throws {
        let groups = ListenerGrouper.group(LsofListenParser.parse(try Fixture.text("lsof-listen-machine.txt")))
        let details: [Int32: ProcessDetails] = [
            650: ProcessDetails(pid: 650, name: "ControlCenter", executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", cwd: "/"),
            678: ProcessDetails(pid: 678, name: "rapportd", executablePath: "/usr/libexec/rapportd", cwd: "/"),
            919: ProcessDetails(pid: 919, name: "HttpToUsbBridge", executablePath: "/Library/Printers/Brother/Utilities/Server/HttpToUsbBridge.app/Contents/MacOS/HttpToUsbBridge", cwd: "/"),
            18_204: ProcessDetails(pid: 18_204, name: "star-mlxd", executablePath: "/Users/star/Applications/STAR.app/Contents/Resources/STARRuntime/bin/star-mlxd", cwd: "/Users/star/dev/star-agent/apps/agent"),
            21_397: ProcessDetails(pid: 21_397, name: "app-server", executablePath: "/Users/star/dev/star-agent/apps/agent/dist/native-workbench/STAR.app/Contents/Resources/STARRuntime/bin/app-server", cwd: "/Users/star/dev/star-agent/apps/agent"),
            21_749: ProcessDetails(pid: 21_749, name: "bun", executablePath: "/Users/star/.bun/bin/bun", cwd: "/Users/star/dev/token-bar/site"),
            64_252: ProcessDetails(pid: 64_252, name: "founder", executablePath: "/Users/star/dev/mln-web/target/debug/founder", cwd: "/Users/star/dev/mln-web"),
        ]
        let visible = groups.filter { IgnoreClassifier.classify($0, details: details[$0.rootPID], config: config) == nil }
        #expect(visible.map(\.port) == [3100, 4173])
    }
}
