/// Where a socket is bound, normalised for probing decisions.
public enum BindAddress: Sendable, Hashable {
    case any
    case loopbackV4
    case loopbackV6
    case other(String)

    public init(raw: String) {
        switch raw {
        case "*", "0.0.0.0", "::": self = .any
        case "127.0.0.1": self = .loopbackV4
        case "::1": self = .loopbackV6
        default: self = .other(raw)
        }
    }

    public var displayText: String {
        switch self {
        case .any: "*"
        case .loopbackV4: "127.0.0.1"
        case .loopbackV6: "[::1]"
        case .other(let raw): raw.contains(":") ? "[\(raw)]" : raw
        }
    }

    fileprivate var sortRank: Int {
        switch self {
        case .any: 0
        case .loopbackV4: 1
        case .loopbackV6: 2
        case .other: 3
        }
    }
}

/// One (family, address) pair a server listens on.
public struct Binding: Sendable, Hashable, Comparable {
    public var family: AddressFamily
    public var address: BindAddress

    public init(family: AddressFamily, address: BindAddress) {
        self.family = family
        self.address = address
    }

    public static func < (lhs: Binding, rhs: Binding) -> Bool {
        if lhs.family != rhs.family { return lhs.family < rhs.family }
        if lhs.address.sortRank != rhs.address.sortRank { return lhs.address.sortRank < rhs.address.sortRank }
        return lhs.address.displayText < rhs.address.displayText
    }
}

/// Chooses loopback hosts to probe. Never returns a LAN address.
public enum ProbeHosts {
    public static let ipv4 = "127.0.0.1"
    public static let ipv6 = "[::1]"

    /// Ordered hosts to try. The second entry (if any) is used only when the
    /// first refuses the connection.
    public static func hosts(for bindings: [Binding]) -> [String] {
        let v4Reachable = bindings.contains { binding in
            binding.address == .loopbackV4
                || binding.address == .any // IPv4 `*`, or an IPv6 dual-stack `*`
        }
        let v6Reachable = bindings.contains { binding in
            binding.address == .loopbackV6 || (binding.family == .ipv6 && binding.address == .any)
        }
        var result: [String] = []
        if v4Reachable { result.append(ipv4) }
        if v6Reachable { result.append(ipv6) }
        return result.isEmpty ? [ipv4] : result
    }
}
