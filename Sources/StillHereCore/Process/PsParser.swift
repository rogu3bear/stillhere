import Foundation

/// Pure parser for `ps -ww -o pid=,ppid=,etime=,command=` lines.
public enum PsParser {
    public struct Row: Sendable, Hashable {
        public var pid: Int32
        public var ppid: Int32
        public var elapsed: TimeInterval
        public var command: String
    }

    public static func parse(_ text: String) -> [Row] {
        text.split(whereSeparator: \.isNewline).compactMap(parseLine)
    }

    static func parseLine(_ line: Substring) -> Row? {
        var rest = line[...]
        guard let pid = nextField(&rest).flatMap({ Int32($0) }),
              let ppid = nextField(&rest).flatMap({ Int32($0) }),
              let elapsed = nextField(&rest).flatMap(parseElapsed)
        else { return nil }
        let command = rest.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        return Row(pid: pid, ppid: ppid, elapsed: elapsed, command: command)
    }

    /// Parses `[[dd-]hh:]mm:ss`.
    public static func parseElapsed<S: StringProtocol>(_ text: S) -> TimeInterval? {
        var days = 0
        var clock = Substring(text)
        if let dash = clock.firstIndex(of: "-") {
            guard let value = Int(clock[..<dash]) else { return nil }
            days = value
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let numbers = parts.compactMap { $0 }
        let (hours, minutes, seconds) = numbers.count == 3
            ? (numbers[0], numbers[1], numbers[2])
            : (0, numbers[0], numbers[1])
        guard minutes < 60, seconds < 60 else { return nil }
        return TimeInterval(((days * 24 + hours) * 60 + minutes) * 60 + seconds)
    }

    private static func nextField(_ rest: inout Substring) -> Substring? {
        rest = rest.drop { $0 == " " || $0 == "\t" }
        guard !rest.isEmpty else { return nil }
        let end = rest.firstIndex { $0 == " " || $0 == "\t" } ?? rest.endIndex
        let field = rest[..<end]
        rest = rest[end...]
        return field
    }
}
