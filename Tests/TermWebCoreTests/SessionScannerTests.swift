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
                let parts = directory.split(separator: "/")
                guard parts.count >= 4, parts[2] == "dev" else { return nil }
                return GitContext(checkoutRoot: "/Users/me/dev/\(parts[3])", branch: "main")
            },
            home: home
        )
    }

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
        #expect(SessionScanner.collisions(found).map(\.sessionPIDs) == [[111, 121]])
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
}
