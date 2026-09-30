/// Address family of a listening socket, as reported by lsof `t` or libproc.
public enum AddressFamily: String, Sendable, Hashable, Codable, Comparable {
    case ipv4
    case ipv6

    public static func < (lhs: AddressFamily, rhs: AddressFamily) -> Bool {
        lhs == .ipv4 && rhs == .ipv6
    }
}

/// One TCP listening socket owned by one process.
public struct ListenerRecord: Sendable, Hashable {
    public var pid: Int32
    public var ppid: Int32?
    /// Process name as reported by the listener source (lsof `c`, may be truncated).
    public var command: String
    public var family: AddressFamily
    /// Raw bind address without brackets: `*`, `127.0.0.1`, `::1`, ...
    public var bindAddress: String
    public var port: Int

    public init(pid: Int32, ppid: Int32?, command: String, family: AddressFamily, bindAddress: String, port: Int) {
        self.pid = pid
        self.ppid = ppid
        self.command = command
        self.family = family
        self.bindAddress = bindAddress
        self.port = port
    }

    public var binding: Binding {
        Binding(family: family, address: BindAddress(raw: bindAddress))
    }
}
