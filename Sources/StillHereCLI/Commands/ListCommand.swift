import Foundation
import StillHereCore

/// `stillhere [list] [--json] [--all] [--mine] [--orphans] [--no-probe]`
struct ListCommand {
    static let usage = """
    stillhere list [--json] [--all] [--mine] [--orphans] [--no-probe]
      --json      machine-readable output (stable keys, ISO 8601 dates)
      --all       include servers hidden by the ignore rules
      --mine      only servers started by the Claude Code session running this command
      --orphans   only servers whose launching agent session has ended
      --no-probe  skip the HTTP status/title check
    """

    let arguments: Arguments
    let output: Output

    init(_ raw: [String], output: Output) throws {
        arguments = try Arguments(raw, booleanFlags: ["json", "all", "mine", "orphans", "no-probe"])
        self.output = output
        guard arguments.positionals.isEmpty else {
            throw Arguments.UsageError(description: "list takes no arguments")
        }
    }

    func run() async throws -> Int32 {
        var filter = ServerQuery.Filter(includeHidden: arguments.flag("all"), orphansOnly: arguments.flag("orphans"))
        if arguments.flag("mine") {
            guard let owner = Caller.owner else {
                output.error("--mine only works inside a Claude Code session (CLAUDE_CODE_SESSION_ID and CLAUDE_PID are not set)")
                return 1
            }
            filter.owner = owner
        }
        let reports = try await ServerQuery.withSavedIgnoreList.reports(filter, probe: !arguments.flag("no-probe"))
        if arguments.flag("json") {
            try output.json(reports)
        } else if reports.isEmpty {
            output.line(emptyMessage(filter))
        } else {
            ServerTable.render(reports, output: output).forEach(output.line)
        }
        return 0
    }

    private func emptyMessage(_ filter: ServerQuery.Filter) -> String {
        if filter.orphansOnly { return "No orphaned servers." }
        if filter.owner != nil { return "No servers started by this session." }
        return filter.includeHidden ? "No listening servers." : "No dev servers running. (--all shows hidden listeners)"
    }
}
