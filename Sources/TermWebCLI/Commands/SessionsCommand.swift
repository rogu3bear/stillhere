import Foundation
import TermWebCore

/// `term-web sessions [--json] [--all] [--check]`
struct SessionsCommand {
    static let usage = """
    term-web sessions [--json] [--all] [--check]
      Lists running coding-agent sessions with the checkouts they work in and the
      servers they started, and warns when independent sessions share a checkout.
      --all    include sessions not working in any git checkout
      --check  for a Claude Code SessionStart hook: print a warning only when
               another independent session is in this session's checkout
    """

    let json: Bool
    let includeIdle: Bool
    let check: Bool
    let output: Output

    init(_ raw: [String], output: Output) throws {
        let arguments = try Arguments(raw, booleanFlags: ["json", "all", "check"])
        guard arguments.positionals.isEmpty else { throw Arguments.UsageError(description: "sessions takes no arguments") }
        json = arguments.flag("json")
        includeIdle = arguments.flag("all")
        check = arguments.flag("check")
        self.output = output
    }

    func run() async throws -> Int32 {
        let caller = SessionScanner.callerSessionPID()
        let overview = SessionOverview(sessions: SessionScanner().scan(), caller: caller)
        if check {
            if let warning = Self.checkWarning(overview, callerPID: caller) { output.line(warning) }
            return 0 // never block the session
        }
        let servers = (try? await ServerQuery().entries(.init(includeHidden: true))) ?? []
        let reports = overview.reports(servers: servers, includeIdle: includeIdle)
        if json {
            try output.json(SessionsResult(sessions: reports, collisions: overview.collisions.map(CollisionReport.init)))
            return 0
        }
        guard !reports.isEmpty else {
            output.line("No agent sessions are working in a git checkout. (--all shows idle ones)")
            return 0
        }
        SessionTable.render(reports, output: output).forEach(output.line)
        for collision in overview.collisions {
            output.line()
            output.line(output.highlight(Self.describe(collision), "33"))
        }
        return 0
    }

    static func describe(_ collision: SessionCollision) -> String {
        let pids = collision.sessionPIDs.map(String.init).joined(separator: ", ")
        return "\(collision.sessionPIDs.count) independent agent sessions share \(collision.checkout.checkoutRoot) "
            + "(\(collision.checkout.headDescription)): PIDs \(pids)"
    }

    /// The hook's message: tells the agent who else is in its checkout, and what to do.
    static func checkWarning(_ overview: SessionOverview, callerPID: Int32?) -> String? {
        // Only the checkout the session itself was started in: that is what "this checkout"
        // means to the agent reading the note, even when its children work elsewhere.
        guard let callerPID,
              let own = overview.sessions.first(where: { $0.pid == callerPID })?.ownCheckout
        else { return nil }
        let mine = overview.collisions.filter {
            $0.sessionPIDs.contains(callerPID) && $0.checkout.checkoutRoot == own.checkoutRoot
        }
        guard !mine.isEmpty else { return nil }
        let byPID = Dictionary(uniqueKeysWithValues: overview.sessions.map { ($0.pid, $0) })
        let lines = mine.map { collision -> String in
            let others = collision.sessionPIDs.filter { $0 != callerPID }.compactMap { byPID[$0] }.map { other in
                "\(other.kind.displayName) PID \(other.pid), running \(UptimeFormatter.string(from: Date().timeIntervalSince(other.startTime)))"
            }
            return "- \(collision.checkout.checkoutRoot) (\(collision.checkout.headDescription)): \(others.joined(separator: "; "))"
        }
        return """
        term-web: another coding-agent session is already working in this checkout.
        \(lines.joined(separator: "\n"))
        Two sessions editing one working tree can overwrite each other's changes. Before editing files, tell the user and ask whether to continue here, wait, or use a separate worktree.
        """
    }
}

struct SessionsResult: Encodable {
    var sessions: [SessionReport]
    var collisions: [CollisionReport]
}

struct CollisionReport: Encodable {
    var checkout: GitContext
    var sessionPIDs: [Int32]

    init(_ collision: SessionCollision) {
        checkout = collision.checkout
        sessionPIDs = collision.sessionPIDs
    }
}

/// Aligned table of sessions; colliding rows are highlighted.
enum SessionTable {
    static let headers = ["AGENT", "PID", "UP", "CHECKOUT", "BRANCH", "SERVERS"]

    static func render(_ reports: [SessionReport], output: Output) -> [String] {
        let rows = reports.map(cells)
        var widths = headers.map(\.count)
        for row in rows { for (column, cell) in row.enumerated() { widths[column] = max(widths[column], cell.count) } }
        func format(_ cells: [String]) -> String {
            cells.enumerated().map { column, cell in
                column == cells.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }
        return [output.highlight(format(headers), "2")] + zip(reports, rows).map { report, row in
            report.collidesIn.isEmpty ? format(row) : output.highlight(format(row), "33")
        }
    }

    static func cells(_ report: SessionReport) -> [String] {
        let home = NSHomeDirectory()
        func short(_ path: String) -> String { path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path }
        var agent = report.parentSessionPID.map { "\(report.agent) (worker of \($0))" } ?? report.agent
        if let reason = report.roleReason { agent += " (\(reason))" }
        return [
            agent,
            String(report.pid),
            UptimeFormatter.string(from: TimeInterval(report.uptimeSeconds)),
            report.checkouts.isEmpty ? "-" : report.checkouts.map { short($0.checkoutRoot) }.joined(separator: ", "),
            report.checkouts.isEmpty ? "-" : report.checkouts.map(ServerTable.branch).joined(separator: ", "),
            report.servers.isEmpty ? "-" : report.servers.map(String.init).joined(separator: ", "),
        ].map(ServerTable.truncate)
    }
}
