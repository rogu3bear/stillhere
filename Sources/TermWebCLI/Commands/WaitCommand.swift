import Foundation
import TermWebCore

/// `term-web wait <port> [--timeout S] [--listen-only] [--json]`
struct WaitCommand {
    static let usage = """
    term-web wait <port> [--timeout SECONDS] [--listen-only] [--json]
      Waits until <port> is listening and answers HTTP, then prints its URL.
      Exits 1 on timeout (default 30 s).
      --listen-only  don't wait for an HTTP response, only for the listener
    """

    let port: Int
    let timeout: Double
    let requireHTTP: Bool
    let json: Bool
    let output: Output

    init(_ raw: [String], output: Output) throws {
        let arguments = try Arguments(raw, booleanFlags: ["listen-only", "json"], valueOptions: ["timeout"])
        port = try arguments.port()
        timeout = try arguments.double("timeout") ?? 30
        requireHTTP = !arguments.flag("listen-only")
        json = arguments.flag("json")
        self.output = output
    }

    func run() async throws -> Int32 {
        let outcome = await ServerWaiter().wait(port: port, timeout: .seconds(timeout), requireHTTP: requireHTTP)
        let report = outcome.entry.map { ServerReport(entry: $0, probe: outcome.probe, now: Date()) }
        if json {
            try output.json(WaitResult(ready: outcome.ready, waitedMilliseconds: outcome.waited.milliseconds, server: report))
        } else if outcome.ready, let report {
            output.line(report.url)
        } else if report != nil {
            output.error("port \(port) is listening but did not answer HTTP within \(Int(timeout)) s")
        } else {
            output.error("nothing listened on port \(port) within \(Int(timeout)) s")
        }
        return outcome.ready ? 0 : 1
    }
}

struct WaitResult: Encodable {
    var ready: Bool
    var waitedMilliseconds: Int
    var server: ServerReport?
}

extension Duration {
    var milliseconds: Int { Int((timeInterval * 1000).rounded()) }
}
