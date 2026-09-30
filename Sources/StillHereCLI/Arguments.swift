/// A tiny, strict argument parser: positionals, boolean flags and `--name value` options.
/// Unknown flags are usage errors rather than silently ignored.
struct Arguments {
    struct UsageError: Error, CustomStringConvertible {
        let description: String
    }

    private(set) var positionals: [String] = []
    private var flags: Set<String> = []
    private var options: [String: String] = [:]

    /// `booleanFlags` and `valueOptions` list the names this command accepts (without `--`).
    init(_ raw: [String], booleanFlags: Set<String>, valueOptions: Set<String> = []) throws {
        var iterator = raw.makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("--"), argument.count > 2 else {
                positionals.append(argument)
                continue
            }
            let body = argument.dropFirst(2)
            let parts = body.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0]
            if valueOptions.contains(name) {
                guard let value = parts.count == 2 ? parts[1] : iterator.next() else {
                    throw UsageError(description: "--\(name) needs a value")
                }
                options[name] = value
            } else if booleanFlags.contains(name), parts.count == 1 {
                flags.insert(name)
            } else {
                throw UsageError(description: "unknown option --\(name)")
            }
        }
    }

    func flag(_ name: String) -> Bool { flags.contains(name) }

    func option(_ name: String) -> String? { options[name] }

    /// Upper bound for durations given in seconds (one day).
    static let maxSeconds: Double = 86_400

    /// A PID option: a positive 32-bit integer.
    func pid(_ name: String) throws -> Int32? {
        guard let value = try int(name) else { return nil }
        guard let pid = Int32(exactly: value), pid > 0 else {
            throw UsageError(description: "--\(name) must be a process ID, got '\(value)'")
        }
        return pid
    }

    func int(_ name: String) throws -> Int? {
        guard let raw = options[name] else { return nil }
        guard let value = Int(raw) else { throw UsageError(description: "--\(name) must be a whole number, got '\(raw)'") }
        return value
    }

    func double(_ name: String) throws -> Double? {
        guard let raw = options[name] else { return nil }
        guard let value = Double(raw), value.isFinite, (0...Self.maxSeconds).contains(value) else {
            throw UsageError(description: "--\(name) must be a number from 0 to \(Int(Self.maxSeconds)), got '\(raw)'")
        }
        return value
    }

    /// A TCP port given as the first positional argument.
    func port(at index: Int = 0) throws -> Int {
        guard positionals.count > index else { throw UsageError(description: "missing port") }
        return try Self.port(positionals[index])
    }

    static func port(_ raw: String) throws -> Int {
        let trimmed = raw.hasPrefix(":") ? String(raw.dropFirst()) : raw
        guard let port = Int(trimmed), (1...65_535).contains(port) else {
            throw UsageError(description: "'\(raw)' is not a TCP port (1-65535)")
        }
        return port
    }
}
