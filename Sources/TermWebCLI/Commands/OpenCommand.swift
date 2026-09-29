import AppKit
import TermWebCore

/// `term-web open <port>`: opens a listed server in the default browser, over HTTPS when
/// the server only speaks TLS.
struct OpenCommand {
    static let usage = """
    term-web open <port>
      Opens the server on <port> in the default browser.
    """

    let port: Int
    let output: Output

    init(_ raw: [String], output: Output) throws {
        let arguments = try Arguments(raw, booleanFlags: [])
        port = try arguments.port()
        self.output = output
    }

    func run() async throws -> Int32 {
        let query = ServerQuery.withSavedIgnoreList
        guard let entry = try await query.entries(.init(includeHidden: true, port: port)).first else {
            output.error("nothing is listening on port \(port)")
            return 1
        }
        let url = entry.url(for: await query.probe(entry))
        guard NSWorkspace.shared.open(url) else {
            output.error("couldn't open \(url.absoluteString)")
            return 1
        }
        output.line(url.absoluteString)
        return 0
    }
}
