/// Which listeners are hidden by default. Structural rules are toggles; the name and
/// port lists are user-editable.
public struct IgnoreConfiguration: Sendable, Hashable, Codable {
    public var hideSystemExecutables: Bool
    public var hideRootCwdDaemons: Bool
    public var hideAppHelpers: Bool
    /// Exact, case-insensitive process names. A trailing `*` is a prefix wildcard.
    public var processNames: [String]
    public var ports: [Int]

    public init(
        hideSystemExecutables: Bool = true,
        hideRootCwdDaemons: Bool = true,
        hideAppHelpers: Bool = true,
        processNames: [String] = IgnoreConfiguration.defaultProcessNames,
        ports: [Int] = IgnoreConfiguration.defaultPorts
    ) {
        self.hideSystemExecutables = hideSystemExecutables
        self.hideRootCwdDaemons = hideRootCwdDaemons
        self.hideAppHelpers = hideAppHelpers
        self.processNames = processNames
        self.ports = ports
    }

    public static let defaults = IgnoreConfiguration()

    /// Hides nothing: used for "show everything" diagnostics and tests.
    public static let none = IgnoreConfiguration(
        hideSystemExecutables: false, hideRootCwdDaemons: false, hideAppHelpers: false,
        processNames: [], ports: []
    )

    public static let defaultProcessNames = [
        "ControlCenter", "rapportd", "sharingd", "AirPlayXPCHelper", "AirPlayUIAgent", "launchd",
        "AssetCache", "AssetCacheLocatorService", "remoted", "HttpToUsbBridge",
        "postgres", "postmaster", "mysqld", "mariadbd", "redis-server", "valkey-server", "mongod",
        "memcached", "clickhouse-server", "influxd", "etcd", "nats-server", "beam.smp", "epmd",
        "Dropbox", "Spotify", "figma_agent", "Raycast", "Code Helper*", "Cursor Helper*", "Adobe*",
    ]

    /// Well-known database/broker ports. Ports that dev servers commonly use are deliberately
    /// absent: 5000 and 7000 (AirPlay is hidden by name because Flask defaults to 5000),
    /// 8123 (`python -m http.server 8123`, Home Assistant) and 9000 (PHP, MinIO).
    /// Interpreter processes are never hidden by port (see `IgnoreClassifier`).
    public static let defaultPorts = [5432, 3306, 6379, 27017, 11211, 9200, 9300, 5672, 15672, 2379, 4222]
}
