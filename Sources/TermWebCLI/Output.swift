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
        FileHandle.standardOutput.write(Data("\(question) [y/N] ".utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        return answer == "y" || answer == "yes"
    }
}

/// The calling agent session, when the CLI itself runs inside one.
enum CallerSession {
    static var id: String? {
        let value = ProcessInfo.processInfo.environment["CLAUDE_CODE_SESSION_ID"]
        return value?.isEmpty == false ? value : nil
    }
}
