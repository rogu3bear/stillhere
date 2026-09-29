import Foundation

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

/// The ignore list is edited in the menu app's Settings and saved in its preferences; the CLI
/// and the MCP server read the same values, so every surface hides the same listeners.
extension IgnoreConfiguration {
    /// The menu app's preferences domain: its bundle identifier (`BUNDLE_ID` in
    /// scripts/common.sh; check-version-sync.sh fails if they differ).
    public static let preferencesDomain = "com.mlnavigator.term-web"

    public enum PreferenceKey {
        public static let hideSystemExecutables = "ignore.hideSystemExecutables"
        public static let hideRootCwdDaemons = "ignore.hideRootCwdDaemons"
        public static let hideAppHelpers = "ignore.hideAppHelpers"
        public static let processNames = "ignore.processNames"
        public static let ports = "ignore.ports"
    }

    /// Saved rules; each missing or malformed value falls back to its default.
    public init(stored value: (String) -> Any?) {
        let base = IgnoreConfiguration.defaults
        self.init(
            hideSystemExecutables: value(PreferenceKey.hideSystemExecutables) as? Bool ?? base.hideSystemExecutables,
            hideRootCwdDaemons: value(PreferenceKey.hideRootCwdDaemons) as? Bool ?? base.hideRootCwdDaemons,
            hideAppHelpers: value(PreferenceKey.hideAppHelpers) as? Bool ?? base.hideAppHelpers,
            processNames: value(PreferenceKey.processNames) as? [String] ?? base.processNames,
            ports: value(PreferenceKey.ports) as? [Int] ?? base.ports
        )
    }

    /// The ignore list saved by the menu app, or the defaults when it saved none (or can't be
    /// read). Read from the app's domain explicitly, whatever process is asking.
    public static func saved(domain: String = preferencesDomain) -> IgnoreConfiguration {
        IgnoreConfiguration(stored: { CFPreferencesCopyAppValue($0 as CFString, domain as CFString) })
    }
}
