import Foundation
import Testing
@testable import TermWebCore

@Suite struct SessionScannerTests {
    let home = "/Users/me"
    let t0 = Date(timeIntervalSince1970: 1_000)

    func record(_ pid: Int32, _ ppid: Int32, _ name: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: ppid, name: name, startTime: t0.addingTimeInterval(TimeInterval(pid)))
    }

    /// cwd by PID; every directory under /Users/me/dev/<repo> maps to that repo's checkout.
    func sessions(_ records: [ProcessRecord], cwds: [Int32: String]) -> [AgentSession] {
        SessionScanner.sessions(
            in: ProcessTable(records),
            cwd: { cwds[$0] },
            checkout: { directory in
                if directory.hasPrefix("/Users/me/dotfiles-home") { return GitContext(checkoutRoot: home, branch: "main") }
                let parts = directory.split(separator: "/")
                guard parts.count >= 4, parts[2] == "dev" else { return nil }
                return GitContext(checkoutRoot: "/Users/me/dev/\(parts[3])", branch: "main")
            },
            home: home,
            now: now
        )
    }

    /// Records start at t0 + pid seconds; "now" is shortly after, so every descendant is
    /// recent unless a test says otherwise.
    var now: Date { t0.addingTimeInterval(500) }

    @Test func twoIndependentTerminalSessionsInOneCheckoutCollide() {
        // The live shape: two iTerm tabs, each running claude in the same repo.
        let found = sessions([
            record(100, 1, "iTerm2"), record(110, 100, "zsh"), record(111, 110, "claude"),
            record(120, 100, "zsh"), record(121, 120, "claude"),
        ], cwds: [111: "/Users/me/dev/web", 121: "/Users/me/dev/web/src"])
        #expect(found.map(\.pid) == [111, 121])
        #expect(found.allSatisfy { $0.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/web"] })
        let collisions = SessionScanner.collisions(found)
        #expect(collisions.map(\.sessionPIDs) == [[111, 121]])
        #expect(collisions.first?.checkout.checkoutRoot == "/Users/me/dev/web")
    }

    @Test func supervisorAndItsWorkerInOneCheckoutDoNotCollide() {
        let found = sessions([
            record(111, 1, "claude"), record(112, 111, "zsh"), record(113, 112, "claude"),
        ], cwds: [111: "/Users/me/dev/web", 113: "/Users/me/dev/web"])
        #expect(found.first { $0.pid == 113 }?.parentSessionPID == 111)
        #expect(SessionScanner.collisions(found).isEmpty)
    }

    @Test func workerPlusAnIndependentSessionStillCollide() {
        let found = sessions([
            record(111, 1, "claude"), record(113, 111, "claude"), record(121, 1, "codex"),
        ], cwds: [111: "/Users/me/dev/web", 113: "/Users/me/dev/web", 121: "/Users/me/dev/web"])
        // Every session in the checkout is listed, workers included.
        #expect(SessionScanner.collisions(found).map(\.sessionPIDs) == [[111, 113, 121]])
    }

    @Test func appHostedAgentWorksInItsChildrensCheckouts() {
        // Codex app server at "/" with threads running tools in two repos.
        let found = sessions([
            record(200, 1, "ChatGPT"), record(201, 200, "codex"),
            record(210, 201, "zsh"), record(211, 210, "node"), record(220, 201, "bun"),
        ], cwds: [201: "/", 211: "/Users/me/dev/api", 220: "/Users/me/dev/web"])
        let codex = found.first { $0.pid == 201 }
        #expect(codex?.kind == .codex)
        #expect(codex?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/api", "/Users/me/dev/web"])
    }

    @Test func nestedSessionsOwnTheirOwnDescendants() {
        let found = sessions([
            record(111, 1, "claude"), record(113, 111, "claude"), record(114, 113, "node"),
        ], cwds: [111: "/Users/me/dev/web", 113: "/", 114: "/Users/me/dev/api"])
        #expect(found.first { $0.pid == 111 }?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/web"])
        #expect(found.first { $0.pid == 113 }?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/api"])
    }

    @Test func rootAndHomeAreNotWorkDirectoriesAndIdleSessionsHaveNoCheckouts() {
        let found = sessions([record(301, 1, "codex")], cwds: [301: "/"])
        #expect(found.first?.isIdle == true)
        #expect(!SessionScanner.isWorkDirectory("/Users/me/", home: home))
        #expect(SessionScanner.isWorkDirectory("/Users/me/dev", home: home))
    }

    @Test func longLivedDescendantsDoNotPlaceASessionInTheirCheckout() {
        // The live false positive: a Codex app server whose preview server and MCP helper
        // were started hours ago in another repo.
        let old = now.addingTimeInterval(-SessionScanner.recentWindow - 60)
        let found = sessions([
            record(201, 1, "codex"),
            ProcessRecord(pid: 210, ppid: 201, name: "bun", startTime: old),
            ProcessRecord(pid: 211, ppid: 201, name: "npm", startTime: old),
            record(220, 201, "zsh"),
        ], cwds: [201: "/", 210: "/Users/me/dev/token-bar", 211: "/Users/me/dev/token-bar", 220: "/Users/me/dev/api"])
        #expect(found.first?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/api"])
        #expect(found.first?.memberPIDs.contains(210) == true) // still linked for server ownership
    }

    @Test func helpersFromTheAgentsOwnAppBundleDoNotPlaceIt() {
        // The live false positive: CCodex (node) runs Claude Code threads beside a stock
        // Codex app server, which starts ChatGPT.app's node_repl in each thread's directory.
        let chatGPT = "/Applications/ChatGPT.app"
        let found = sessions([
            record(100, 1, "node"),
            ProcessRecord(pid: 201, ppid: 100, name: "codex", startTime: t0, appBundle: chatGPT, isAppServer: true),
            ProcessRecord(pid: 202, ppid: 201, name: "node_repl", startTime: now, appBundle: chatGPT),
            record(110, 100, "claude"),
        ], cwds: [100: "/Users/me/dev/bridge", 201: "/Users/me/dev/bridge", 202: "/Users/me/dev/web", 110: "/Users/me/dev/web"])
        #expect(found.first { $0.pid == 201 }?.checkouts.isEmpty == true)
        #expect(SessionScanner.collisions(found, now: now).isEmpty)

        // A command the app server runs there still places it.
        let working = sessions([
            ProcessRecord(pid: 201, ppid: 1, name: "codex", startTime: t0, appBundle: chatGPT, isAppServer: true),
            ProcessRecord(pid: 202, ppid: 201, name: "node_repl", startTime: now, appBundle: chatGPT),
            record(203, 201, "zsh"),
            record(110, 1, "claude"),
        ], cwds: [202: "/Users/me/dev/web", 203: "/Users/me/dev/web", 110: "/Users/me/dev/web"])
        #expect(SessionScanner.collisions(working, now: now).map(\.sessionPIDs) == [[110, 201]])
    }

    @Test func anAppServersOwnDirectoryDoesNotPlaceIt() {
        // The live false positive: CCodex, started in its own repo, launches the Codex app
        // server there, so every Claude thread opened in that repo "collided" with it.
        let found = sessions([
            record(100, 1, "node"),
            ProcessRecord(pid: 201, ppid: 100, name: "codex", startTime: t0, isAppServer: true),
            record(110, 100, "claude"),
        ], cwds: [100: "/Users/me/dev/bridge", 201: "/Users/me/dev/bridge", 110: "/Users/me/dev/bridge"])
        let server = found.first { $0.pid == 201 }
        #expect(server?.checkouts.isEmpty == true)
        #expect(server?.ownCheckout == nil)
        #expect(server?.cwd == "/Users/me/dev/bridge") // still reported
        #expect(found.first { $0.pid == 110 }?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/bridge"])
        #expect(SessionScanner.collisions(found, now: now).isEmpty)

        // A command it runs there still places it.
        let working = sessions([
            ProcessRecord(pid: 201, ppid: 1, name: "codex", startTime: t0, isAppServer: true),
            record(203, 201, "zsh"),
            record(110, 1, "claude"),
        ], cwds: [201: "/Users/me/dev/bridge", 203: "/Users/me/dev/bridge", 110: "/Users/me/dev/bridge"])
        #expect(SessionScanner.collisions(working, now: now).map(\.sessionPIDs) == [[110, 201]])

        // A Codex CLI session started in a repo works there, as any terminal agent does.
        let terminal = sessions([record(301, 1, "codex"), record(110, 1, "claude")],
                                cwds: [301: "/Users/me/dev/bridge", 110: "/Users/me/dev/bridge"])
        #expect(SessionScanner.collisions(terminal, now: now).map(\.sessionPIDs) == [[110, 301]])
    }

    @Test func appServerIsTheExactSubcommand() {
        #expect(ProcessRecord.isAppServer(argv: ["codex", "app-server", "--listen", "unix://"]))
        #expect(ProcessRecord.isAppServer(argv: ["codex", "-c", "model=o3", "app-server"]))
        #expect(!ProcessRecord.isAppServer(argv: ["codex", "exec", "restart the app-server"]))
        #expect(!ProcessRecord.isAppServer(argv: ["app-server"])) // argv[0] is the program
        #expect(!ProcessRecord.isAppServer(argv: ["claude", "--resume"]))
    }

    @Test func appBundleIsTheOutermostBundle() {
        #expect(ProcessRecord.appBundle(containing: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex") == "/Applications/ChatGPT.app")
        #expect(ProcessRecord.appBundle(containing: "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl") == "/Applications/ChatGPT.app")
        #expect(ProcessRecord.appBundle(containing: "/Users/me/.local/share/claude/versions/2.1.280") == nil)
        #expect(ProcessRecord.appBundle(containing: "/opt/homebrew/bin/node.app-helper") == nil)
    }

    @Test func aDotfilesRepoAtHomeIsNotACheckout() {
        let found = sessions([record(111, 1, "claude"), record(121, 1, "claude")],
                             cwds: [111: "/Users/me/dotfiles-home/a", 121: "/Users/me/dotfiles-home/b"])
        #expect(found.allSatisfy { $0.isIdle })
        #expect(SessionScanner.collisions(found).isEmpty)
    }

    @Test func workersOfOneSupervisorNeverCollideWhereverTheSupervisorIs() {
        let found = sessions([
            record(111, 1, "claude"), record(112, 111, "claude"), record(113, 111, "claude"),
        ], cwds: [111: "/Users/me/dev/api", 112: "/Users/me/dev/web", 113: "/Users/me/dev/web"])
        #expect(SessionScanner.collisions(found).isEmpty)
    }

    @Test func nodeWrapperAndItsNativeAgentAreOneSession() {
        var wrapper = record(300, 1, "node")
        wrapper.agentKind = .codex
        let found = sessions([wrapper, record(301, 300, "codex")], cwds: [300: "/Users/me/dev/web", 301: "/Users/me/dev/web"])
        #expect(found.map(\.pid) == [301])
        #expect(found.first?.parentSessionPID == nil)
    }

    @Test func npmSessionWithOneDelegatedWorkerIsNotAWrapper() {
        // node claude (npm install) -> sh (Bash tool) -> claude -p worker.
        var supervisor = record(400, 1, "node")
        supervisor.agentKind = .claudeCode
        let found = sessions([supervisor, record(401, 400, "sh"), record(402, 401, "claude")],
                             cwds: [400: "/Users/me/dev/web", 402: "/Users/me/dev/web"])
        #expect(found.map(\.pid) == [400, 402])
        #expect(found.first { $0.pid == 402 }?.parentSessionPID == 400)
    }

    @Test func ownCheckoutIsOnlyTheSessionsOwnDirectory() {
        // Started in ~, now running a command in a repo: working there, but not started there.
        let found = sessions([record(111, 1, "claude"), record(112, 111, "zsh")],
                             cwds: [111: home, 112: "/Users/me/dev/web"])
        #expect(found.first?.checkouts.map(\.checkoutRoot) == ["/Users/me/dev/web"])
        #expect(found.first?.ownCheckout == nil)
        #expect(AgentSession(pid: 1, kind: .codex, startTime: t0, checkouts: [GitContext(checkoutRoot: "/Users/me/dev/web")]).ownCheckout == nil)
    }

    @Test func brandNewSessionsDoNotCollideUnlessTheyAreTheCaller() {
        let web = GitContext(checkoutRoot: "/Users/me/dev/web")
        let now = t0.addingTimeInterval(100)
        let sessions = [
            AgentSession(pid: 1, kind: .claudeCode, startTime: t0, checkouts: [web]),
            AgentSession(pid: 2, kind: .claudeCode, startTime: now.addingTimeInterval(-1), checkouts: [web]),
        ]
        #expect(SessionScanner.collisions(sessions, now: now).isEmpty)
        #expect(SessionScanner.collisions(sessions, now: now, alwaysEligible: 2).map(\.sessionPIDs) == [[1, 2]])
    }

    @Test func cyclicTablesTerminate() {
        let table = ProcessTable([record(5, 6, "a"), record(6, 5, "claude")])
        #expect(table.ancestors(of: 5).count <= 2)
        #expect(table.descendants(of: 5).count <= 2)
    }

    @Test func liveSnapshotSeesThisProcess() {
        let table = ProcessTable.snapshot()
        #expect(table.records[getpid()] != nil)
        #expect(table.records.count > 10)
    }
}

@Suite struct SessionOverviewTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func checkout(_ name: String) -> GitContext { GitContext(checkoutRoot: "/Users/me/dev/\(name)", branch: "main") }

    @Test func collidingSessionsComeFirstAndWorkersFollowTheirParent() {
        let overview = SessionOverview(sessions: [
            AgentSession(pid: 10, kind: .claudeCode, startTime: t0, checkouts: [checkout("api")]),
            AgentSession(pid: 11, kind: .claudeCode, startTime: t0, checkouts: [checkout("api")], parentSessionPID: 10),
            AgentSession(pid: 20, kind: .claudeCode, startTime: t0, checkouts: [checkout("web")]),
            AgentSession(pid: 30, kind: .codex, startTime: t0, checkouts: [checkout("web")]),
            AgentSession(pid: 40, kind: .codex, startTime: t0),
        ])
        #expect(overview.displayOrder.map { [$0.session.pid, Int32($0.depth)] } == [[20, 0], [30, 0], [10, 0], [11, 1]])
        #expect(overview.collisionPartners(of: overview.sessions[2]) == [30])
        #expect(overview.collisionPartners(of: overview.sessions[0]).isEmpty)
    }

    @Test func partnersSharingSeveralCheckoutsAreListedOnce() {
        let overview = SessionOverview(sessions: [
            AgentSession(pid: 1, kind: .claudeCode, startTime: t0, checkouts: [checkout("api"), checkout("web")]),
            AgentSession(pid: 2, kind: .codex, startTime: t0, checkouts: [checkout("api"), checkout("web")]),
        ])
        #expect(overview.collisions.count == 2)
        #expect(overview.collisionPartners(of: overview.sessions[0]) == [2])
    }
}
