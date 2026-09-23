import Foundation
import Testing
@testable import TermWebCore

@Suite struct AgentDetectorTests {
    let serverStart = Date(timeIntervalSince1970: 2_000)

    func process(_ pid: Int32, name: String, start: TimeInterval = 1_000) -> ProcessDetails {
        ProcessDetails(pid: pid, name: name, startTime: Date(timeIntervalSince1970: start))
    }

    @Test func claudeCodeWithLiveLauncher() throws {
        let context = try #require(AgentDetector.detect(
            environment: ["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "s-1", "CLAUDE_PID": "7820"],
            ancestors: [],
            serverStart: serverStart,
            lookup: { $0 == 7820 ? process(7820, name: "claude") : nil }
        ))
        #expect(context.kind == .claudeCode)
        #expect(context.evidence == .environment)
        #expect(context.sessionID == "s-1")
        #expect(context.launcherPID == 7820)
        #expect(context.launcherAlive == true)
        #expect(!context.isOrphaned)
    }

    @Test func claudeCodeWhoseSessionEndedIsOrphaned() throws {
        let context = try #require(AgentDetector.detect(
            environment: ["CLAUDECODE": "1", "CLAUDE_PID": "7820"],
            ancestors: [], serverStart: serverStart, lookup: { _ in nil }
        ))
        #expect(context.isOrphaned)
    }

    @Test func reusedLauncherPIDCountsAsGone() throws {
        let context = try #require(AgentDetector.detect(
            environment: ["CLAUDECODE": "1", "CLAUDE_PID": "7820"],
            ancestors: [], serverStart: serverStart,
            lookup: { _ in process(7820, name: "zsh", start: 3_000) }
        ))
        #expect(context.isOrphaned)
    }

    @Test func codexFromSandboxMarkerIsNeverClaimedOrphaned() throws {
        let context = try #require(AgentDetector.detect(
            environment: ["CODEX_SANDBOX": "seatbelt"], ancestors: [], serverStart: serverStart, lookup: { _ in nil }
        ))
        #expect(context.kind == .codex)
        #expect(context.launcherAlive == nil)
        #expect(!context.isOrphaned)
    }

    @Test func environmentAgentGainsLauncherFromLiveAncestor() throws {
        let context = try #require(AgentDetector.detect(
            environment: ["CODEX_SANDBOX": "seatbelt"],
            ancestors: [process(50, name: "zsh"), process(40, name: "codex")],
            serverStart: serverStart, lookup: { _ in nil }
        ))
        #expect(context.launcherPID == 40)
        #expect(context.launcherAlive == true)
    }

    @Test func aiAgentMarkerNamesTheAgent() {
        #expect(AgentDetector.agentName(fromMarker: "claude-code_2-1-280_agent") == .claudeCode)
        #expect(AgentDetector.agentName(fromMarker: "codex") == .codex)
        #expect(AgentDetector.agentName(fromMarker: "goose_1_agent") == .other("goose"))
        #expect(AgentDetector.agentName(fromMarker: "") == nil)
    }

    @Test func ancestryAloneFindsTheNearestAgent() throws {
        let context = try #require(AgentDetector.detect(
            environment: [:],
            ancestors: [process(60, name: "node"), process(50, name: "zsh"), process(40, name: "cursor-agent")],
            serverStart: serverStart, lookup: { _ in nil }
        ))
        #expect(context.kind == .other("Cursor"))
        #expect(context.evidence == .ancestry)
        #expect(context.launcherPID == 40)
    }

    @Test func plainProcessesHaveNoAgent() {
        #expect(AgentDetector.detect(
            environment: [:], ancestors: [process(50, name: "zsh"), process(40, name: "login")],
            serverStart: serverStart, lookup: { _ in nil }
        ) == nil)
    }
}

@Suite struct GitReaderTests {
    /// A fake filesystem: directories and file contents by absolute path.
    struct FakeFS {
        var directories: Set<String> = []
        var files: [String: String] = [:]

        func context(_ directory: String, home: String = "/Users/me") -> GitContext? {
            GitReader.context(
                for: directory, home: home,
                read: { files[$0] },
                isDirectory: { path in
                    directories.contains(path) ? true : (files[path] != nil ? false : nil)
                }
            )
        }
    }

    @Test func branchFromMainCheckoutAboveTheProject() {
        var fs = FakeFS()
        fs.directories = ["/Users/me/dev/shop/.git"]
        fs.files["/Users/me/dev/shop/.git/HEAD"] = "ref: refs/heads/feat/cart\n"
        let git = fs.context("/Users/me/dev/shop/apps/web")
        #expect(git == GitContext(checkoutRoot: "/Users/me/dev/shop", branch: "feat/cart"))
        #expect(git?.headDescription == "feat/cart")
    }

    @Test func linkedWorktreeReportsItsNameAndBranch() {
        var fs = FakeFS()
        fs.files["/Users/me/dev/shop-wt/.git"] = "gitdir: /Users/me/dev/shop/.git/worktrees/shop-wt\n"
        fs.files["/Users/me/dev/shop/.git/worktrees/shop-wt/HEAD"] = "ref: refs/heads/fix/login\n"
        let git = fs.context("/Users/me/dev/shop-wt")
        #expect(git?.worktree == "shop-wt")
        #expect(git?.branch == "fix/login")
        #expect(git?.checkoutRoot == "/Users/me/dev/shop-wt")
    }

    @Test func relativeGitdirPointerResolvesFromTheCheckout() {
        var fs = FakeFS()
        fs.files["/Users/me/dev/a/wt/.git"] = "gitdir: ../.git/worktrees/wt"
        fs.files["/Users/me/dev/a/.git/worktrees/wt/HEAD"] = "ref: refs/heads/x"
        #expect(fs.context("/Users/me/dev/a/wt")?.branch == "x")
    }

    @Test func detachedHead() {
        var fs = FakeFS()
        fs.directories = ["/Users/me/r/.git"]
        fs.files["/Users/me/r/.git/HEAD"] = "4f9c2d1e8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d\n"
        let git = fs.context("/Users/me/r")
        #expect(git?.branch == nil)
        #expect(git?.headDescription == "detached 4f9c2d1")
    }

    @Test func stopsAtHomeWithoutARepository() {
        var fs = FakeFS()
        fs.directories = ["/Users/.git"] // above home: must not be found
        fs.files["/Users/.git/HEAD"] = "ref: refs/heads/main"
        #expect(fs.context("/Users/me/scratch") == nil)
    }
}
