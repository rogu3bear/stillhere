import Foundation
import Testing
@testable import StillHereCore

@Suite struct SessionRoleTests {
    @Test func iTermCodeReviewIsAReviewer() {
        // The argv iTerm2 3.7 used for its built-in review (seen live as PID 31201).
        let argv = [
            "claude", "Review the pending changes in this repo. …",
            "--append-system-prompt-file", "/var/folders/xx/T/iterm2-code-review-system-prompt-1234.txt",
            "--settings", "/Applications/iTerm.app/Contents/Resources/code-review-settings.txt",
        ]
        #expect(SessionRoleClassifier.role(argv: argv) == .reviewer(reason: "iTerm2 code review"))
    }

    @Test func explicitReadOnlyLaunchesAreReviewers() {
        #expect(SessionRoleClassifier.role(argv: ["claude", "--permission-mode", "plan"]) == .reviewer(reason: "plan mode"))
        #expect(SessionRoleClassifier.role(argv: ["claude", "--permission-mode=plan"]) == .reviewer(reason: "plan mode"))
        #expect(SessionRoleClassifier.role(argv: ["claude", "--disallowedTools", "Edit", "Write", "-p", "x"]) == .reviewer(reason: "edits disallowed"))
        #expect(SessionRoleClassifier.role(argv: ["claude", "--disallowed-tools=Edit,Write,NotebookEdit"]) == .reviewer(reason: "edits disallowed"))
        #expect(SessionRoleClassifier.role(argv: ["codex", "exec", "-s", "read-only", "review"]) == .reviewer(reason: "read-only sandbox"))
        #expect(SessionRoleClassifier.role(argv: ["codex", "--sandbox=read-only"]) == .reviewer(reason: "read-only sandbox"))
    }

    @Test func everythingElseIsAWriter() {
        #expect(SessionRoleClassifier.role(argv: ["claude"]) == .writer)
        #expect(SessionRoleClassifier.role(argv: ["claude", "--permission-mode", "acceptEdits"]) == .writer)
        #expect(SessionRoleClassifier.role(argv: ["claude", "--disallowedTools", "Edit"]) == .writer) // Write still allowed
        #expect(SessionRoleClassifier.role(argv: ["claude", "--settings", "/Users/me/review-settings.json"]) == .writer)
        #expect(SessionRoleClassifier.role(argv: ["codex", "-s", "workspace-write"]) == .writer)
        // A prompt that merely mentions a flag is not a flag.
        #expect(SessionRoleClassifier.role(argv: ["claude", "use --permission-mode plan later"]) == .writer)
    }

    @Test func reviewersNeverCollide() {
        let web = GitContext(checkoutRoot: "/Users/me/dev/web")
        let t0 = Date(timeIntervalSince1970: 0)
        let writerAndReviewer = [
            AgentSession(pid: 1, kind: .claudeCode, startTime: t0, checkouts: [web]),
            AgentSession(pid: 2, kind: .claudeCode, startTime: t0, checkouts: [web], role: .reviewer(reason: "iTerm2 code review")),
        ]
        #expect(SessionScanner.collisions(writerAndReviewer, now: t0.addingTimeInterval(60)).isEmpty)
        let twoWriters = writerAndReviewer + [AgentSession(pid: 3, kind: .codex, startTime: t0, checkouts: [web])]
        #expect(SessionScanner.collisions(twoWriters, now: t0.addingTimeInterval(60)).map(\.sessionPIDs) == [[1, 3]])
    }

    @Test func reportsCarryTheRole() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        let report = SessionReport(
            session: AgentSession(pid: 2, kind: .claudeCode, startTime: t0, role: .reviewer(reason: "plan mode")),
            servers: [], collisions: [], now: t0
        )
        let json = String(decoding: try ServerReport.encoder().encode(report), as: UTF8.self)
        #expect(json.contains("\"role\" : \"reviewer\""))
        #expect(json.contains("\"roleReason\" : \"plan mode\""))
    }
}
