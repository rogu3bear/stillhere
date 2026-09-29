import Foundation
import TermWebCore

/// Where the CLI writes, plus the facts about the terminal that shape output.
struct Output {
    var isTerminal = isatty(STDOUT_FILENO) == 1
    var inputIsTerminal = isatty(STDIN_FILENO) == 1
    var useColor = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    func line(_ text: String = "") {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    func error(_ text: String) {
        FileHandle.standardError.write(Data(("term-web: " + text + "\n").utf8))
    }

    func json(_ value: some Encodable) throws {
        let data = try ServerReport.encoder().encode(value)
        line(String(decoding: data, as: UTF8.self))
    }

    func highlight(_ text: String, _ code: String) -> String {
        useColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    /// Asks on the terminal; false when stdin is not a terminal.
    func confirm(_ question: String) -> Bool {
        guard inputIsTerminal else { return false }
        // stderr, so the question stays visible when stdout is piped.
        FileHandle.standardError.write(Data("\(question) [y/N] ".utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        return answer == "y" || answer == "yes"
    }
}

/// The calling agent, when the CLI itself runs inside a Claude Code session.
enum Caller {
    static var owner: AgentOwner? { AgentOwner(environment: ProcessInfo.processInfo.environment) }
}

extension ServerQuery {
    /// What every command and the MCP server scan with: the ignore list saved in the menu
    /// app's Settings, re-read on every scan, so all surfaces hide the same listeners.
    static var withSavedIgnoreList: ServerQuery { ServerQuery(rules: { .saved() }) }
}
