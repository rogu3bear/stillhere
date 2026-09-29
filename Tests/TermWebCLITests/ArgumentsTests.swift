import Foundation
import Testing
import TermWebCore
@testable import TermWebCLI

@Suite struct ArgumentsTests {
    @Test func parsesFlagsOptionsAndPositionals() throws {
        let arguments = try Arguments(["5173", "--pid", "42", "--yes", "--timeout=2.5"], booleanFlags: ["yes"], valueOptions: ["pid", "timeout"])
        #expect(try arguments.port() == 5173)
        #expect(try arguments.int("pid") == 42)
        #expect(try arguments.double("timeout") == 2.5)
        #expect(arguments.flag("yes"))
        #expect(!arguments.flag("force"))
    }

    @Test func rejectsUnknownFlagsAndMissingValues() {
        #expect(throws: Arguments.UsageError.self) { try Arguments(["--nope"], booleanFlags: ["yes"]) }
        #expect(throws: Arguments.UsageError.self) { try Arguments(["--pid"], booleanFlags: [], valueOptions: ["pid"]) }
        #expect(throws: Arguments.UsageError.self) { try Arguments(["--yes=1"], booleanFlags: ["yes"]) }
    }

    @Test func portsAcceptAColonPrefixAndRejectNonsense() throws {
        #expect(try Arguments.port(":3000") == 3000)
        #expect(throws: Arguments.UsageError.self) { try Arguments.port("0") }
        #expect(throws: Arguments.UsageError.self) { try Arguments.port("70000") }
        #expect(throws: Arguments.UsageError.self) { try Arguments.port("abc") }
        #expect(throws: Arguments.UsageError.self) { try Arguments([], booleanFlags: []).port() }
    }
}

@Suite struct ServerTableTests {
    func report(_ entry: ServerEntry) -> ServerReport {
        ServerReport(entry: entry, probe: SampleServers.probes[entry.port], now: SampleServers.referenceDate)
    }

    @Test func showsBranchWorktreeAgentAndOrphanState() {
        let cells = ServerTable.cells(report(SampleServers.next))
        #expect(cells[0] == "http://localhost:3000/")
        #expect(cells[3] == "fix/rss (wt blog-wt)")
        #expect(cells[4] == "Claude Code (orphaned)")
        #expect(cells[6] == "200")
        #expect(cells[7] == "My Blog")
    }

    @Test func alignsColumnsWithoutColorWhenNotATerminal() {
        var output = Output()
        output.useColor = false
        let lines = ServerTable.render([report(SampleServers.vite), report(SampleServers.next)], output: output)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("URL"))
        let agentColumn = lines[0].range(of: "AGENT")!.lowerBound.utf16Offset(in: lines[0])
        #expect(lines.dropFirst().allSatisfy { $0.count > agentColumn })
        #expect(!lines.joined().contains("\u{1B}"))
    }

    @Test func truncatesLongCells() {
        #expect(ServerTable.truncate(String(repeating: "x", count: 50)).count == ServerTable.maxCell)
        #expect(ServerTable.truncate("short") == "short")
    }
}

@Suite struct CommandDispatchTests {
    @Test func usageErrorsExitTwoAndUnknownCommandsAreRejected() async {
        var output = Output()
        output.useColor = false
        #expect(await TermWebCLI.run(["frobnicate"], output: output) == 2)
        #expect(await TermWebCLI.run(["stop"], output: output) == 2)
        #expect(await TermWebCLI.run(["wait", "notaport"], output: output) == 2)
        #expect(await TermWebCLI.run(["version"], output: output) == 0)
        #expect(await TermWebCLI.run(["wait", "3000", "--timeout", "inf"], output: output) == 2)
        #expect(await TermWebCLI.run(["wait", "3000", "--timeout", "1e300"], output: output) == 2)
        #expect(await TermWebCLI.run(["stop", "3000", "--pid", "5000000000"], output: output) == 2)
        #expect(await TermWebCLI.run(["stop", "--orphans", "--pid", "42"], output: output) == 2)
    }
}

@Suite struct SessionsCheckTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func overview() -> SessionOverview {
        let web = GitContext(checkoutRoot: "/Users/me/dev/web", branch: "main")
        return SessionOverview(sessions: [
            AgentSession(pid: 111, kind: .claudeCode, startTime: t0, ownCheckout: web, checkouts: [web]),
            AgentSession(pid: 121, kind: .codex, startTime: t0, checkouts: [web]),
            AgentSession(pid: 131, kind: .claudeCode, startTime: t0, checkouts: [GitContext(checkoutRoot: "/Users/me/dev/api")]),
        ])
    }

    @Test func warnsOnlyTheSessionsInACollision() {
        let warning = SessionsCommand.checkWarning(overview(), callerPID: 111)
        #expect(warning?.contains("/Users/me/dev/web (main): Codex PID 121") == true)
        #expect(warning?.contains("Unless the user has already told you how to proceed") == true)
        #expect(warning?.contains("ask whether to continue here or wait for the other session to finish") == true)
        #expect(warning?.contains("worktree") == false)
        #expect(SessionsCommand.checkWarning(overview(), callerPID: 131) == nil)

        // A caller whose own checkout is elsewhere hears nothing about its children's.
        let api = GitContext(checkoutRoot: "/Users/me/dev/api")
        let web = GitContext(checkoutRoot: "/Users/me/dev/web", branch: "main")
        let elsewhere = SessionOverview(sessions: [
            AgentSession(pid: 111, kind: .claudeCode, startTime: t0, ownCheckout: api, checkouts: [api, web]),
            AgentSession(pid: 121, kind: .codex, startTime: t0, checkouts: [web]),
        ])
        #expect(!elsewhere.collisions.isEmpty)
        #expect(SessionsCommand.checkWarning(elsewhere, callerPID: 111) == nil)
        #expect(SessionsCommand.checkWarning(overview(), callerPID: nil) == nil)
    }

    @Test func tableMarksWorkersAndShortensHome() {
        let report = SessionReport(
            session: AgentSession(pid: 9, kind: .claudeCode, startTime: t0,
                                  checkouts: [GitContext(checkoutRoot: NSHomeDirectory() + "/dev/web", branch: "x")],
                                  parentSessionPID: 7),
            servers: [], collisions: [], now: t0.addingTimeInterval(90)
        )
        let cells = SessionTable.cells(report)
        #expect(cells[0] == "Claude Code (worker of 7)")
        #expect(cells[2] == "1m")
        #expect(cells[3] == "~/dev/web")
        #expect(cells[5] == "-")
    }
}
