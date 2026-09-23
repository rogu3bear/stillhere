import Foundation
import TermWebCore

/// Aligned plain-text table of servers for humans; `--json` is the machine format.
enum ServerTable {
    static let headers = ["URL", "FRAMEWORK", "PROJECT", "BRANCH", "AGENT", "UP", "HTTP", "TITLE"]
    static let maxCell = 36

    static func render(_ reports: [ServerReport], output: Output) -> [String] {
        let rows = reports.map(cells)
        var widths = headers.map(\.count)
        for row in rows {
            for (column, cell) in row.enumerated() { widths[column] = max(widths[column], cell.count) }
        }
        func format(_ cells: [String]) -> String {
            cells.enumerated().map { column, cell in
                column == cells.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces)
        }
        var lines = [output.highlight(format(headers), "2")]
        for (report, row) in zip(reports, rows) {
            let text = format(row)
            lines.append(report.agent?.orphaned == true ? output.highlight(text, "33") : text)
        }
        return lines
    }

    static func cells(_ report: ServerReport) -> [String] {
        [
            report.url,
            report.framework,
            report.project?.name ?? "-",
            branch(report.git),
            agent(report.agent),
            report.uptimeSeconds.map { UptimeFormatter.string(from: TimeInterval($0)) } ?? "-",
            http(report.http),
            report.http?.title ?? "",
        ].map(truncate)
    }

    static func branch(_ git: GitContext?) -> String {
        guard let git else { return "-" }
        if let worktree = git.worktree { return "\(git.headDescription) (wt \(worktree))" }
        return git.headDescription
    }

    static func agent(_ agent: ServerReport.Agent?) -> String {
        guard let agent else { return "-" }
        return agent.orphaned ? "\(agent.name) (orphaned)" : agent.name
    }

    static func http(_ http: ServerReport.HTTP?) -> String {
        guard let http else { return "-" }
        if let status = http.status { return String(status) }
        return http.error ?? "-"
    }

    static func truncate(_ cell: String) -> String {
        cell.count > maxCell ? String(cell.prefix(maxCell - 1)) + "…" : cell
    }
}
