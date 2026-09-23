/// Pure parser for `lsof -F pcRtn` output (one field per line, first char is the field id).
///
/// Process sets start with `p<pid>` followed by `R<ppid>` and `c<command>`; each file
/// set starts with `f<fd>`, then `t<IPv4|IPv6>` and `n<address>:<port>`.
/// Unknown fields are ignored and malformed lines are skipped.
public enum LsofListenParser {
    public static func parse(_ text: String) -> [ListenerRecord] {
        var records: [ListenerRecord] = []
        var process: (pid: Int32, ppid: Int32?, command: String)?
        var family: AddressFamily?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                process = Int32(value).map { (pid: $0, ppid: nil, command: "") }
                family = nil
            case "R":
                process?.ppid = Int32(value)
            case "c":
                process?.command = value
            case "f":
                family = nil
            case "t":
                family = switch value {
                case "IPv4": .ipv4
                case "IPv6": .ipv6
                default: nil
                }
            case "n":
                guard let process, let family, let parsed = parseAddress(value) else { continue }
                records.append(ListenerRecord(
                    pid: process.pid,
                    ppid: process.ppid,
                    command: process.command,
                    family: family,
                    bindAddress: parsed.address,
                    port: parsed.port
                ))
            default:
                continue
            }
        }
        return records
    }

    /// Splits `*:5000`, `127.0.0.1:8765` or `[::1]:5173` into address and port.
    /// Connected sockets (`a->b`) and malformed names return nil.
    static func parseAddress(_ name: String) -> (address: String, port: Int)? {
        guard !name.contains("->"), let colon = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: colon)...]), (1...65_535).contains(port) else { return nil }
        var address = Substring(name[..<colon])
        if address.hasPrefix("[") {
            guard address.hasSuffix("]") else { return nil }
            address = address.dropFirst().dropLast()
        }
        guard !address.isEmpty else { return nil }
        return (address: String(address), port: port)
    }
}
