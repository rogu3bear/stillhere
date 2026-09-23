import Foundation
import TermWebCore

/// `term-web stop <port> [--pid N]` or `term-web stop --orphans`, with `--yes` / `--force`.
struct StopCommand {
    static let usage = """
    term-web stop <port> [--pid PID] [--yes] [--force]
    term-web stop --orphans [--yes] [--force]
      Sends SIGTERM and waits for the server to exit. Asks first unless --yes;
      without a terminal to ask on, --yes is required.
      --pid      choose between unrelated processes sharing <port>
      --orphans  stop every server whose launching agent session has ended
      --force    send SIGKILL to the same process if SIGTERM didn't stop it
    System, daemon and app-helper processes are never stopped.
    """

    let port: Int?
    let pid: Int32?
    let orphans: Bool
    let assumeYes: Bool
    let force: Bool
    let output: Output

    init(_ raw: [String], output: Output) throws {
        let arguments = try Arguments(raw, booleanFlags: ["orphans", "yes", "force"], valueOptions: ["pid"])
        orphans = arguments.flag("orphans")
        if orphans {
            guard arguments.positionals.isEmpty else { throw Arguments.UsageError(description: "--orphans takes no port") }
            port = nil
        } else {
            port = try arguments.port()
        }
        pid = try arguments.int("pid").map(Int32.init)
        assumeYes = arguments.flag("yes")
        force = arguments.flag("force")
        self.output = output
    }

    func run() async throws -> Int32 {
        let targets = try await selectTargets()
        guard !targets.isEmpty else { return 1 }
        guard assumeYes || output.confirm(question(targets)) else {
            output.error(output.inputIsTerminal ? "not stopped" : "not stopped: pass --yes to stop without a terminal to confirm on")
            return 1
        }
        let stopper = ServerStopper()
        var failures = 0
        for entry in targets {
            let result = await stopper.stop(entry, force: force)
            let label = "\(entry.processName) (PID \(entry.rootPID)) on port \(entry.port)"
            if result.succeeded {
                output.line("\(label): \(result.message)")
            } else {
                output.error("\(label): \(result.message)")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    private func selectTargets() async throws -> [ServerEntry] {
        let query = ServerQuery()
        if orphans {
            let found = try await query.entries(.init(orphansOnly: true))
            if found.isEmpty { output.line("No orphaned servers.") }
            return found
        }
        guard let port else { return [] }
        var found = try await query.entries(.init(includeHidden: true, port: port))
        if let pid { found = found.filter { $0.rootPID == pid } }
        switch found.count {
        case 0:
            output.error(pid.map { "PID \($0) is not listening on port \(port)" } ?? "nothing is listening on port \(port)")
            return []
        case 1:
            return found
        default:
            let pids = found.map { "\($0.rootPID) (\($0.processName))" }.joined(separator: ", ")
            output.error("\(found.count) unrelated processes listen on port \(port): \(pids). Choose one with --pid.")
            return []
        }
    }

    private func question(_ targets: [ServerEntry]) -> String {
        if targets.count == 1, let entry = targets.first {
            return "Stop \(entry.processName) (PID \(entry.rootPID)) on port \(entry.port)?"
        }
        return "Stop \(targets.count) orphaned servers on ports \(targets.map { String($0.port) }.joined(separator: ", "))?"
    }
}
