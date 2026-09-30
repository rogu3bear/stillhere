import Foundation

/// Carries only product-owned settings across the first-public-release rename.
/// Legacy settings remain intact, and values already saved under the new identity win.
public enum ProductPreferences {
    static let legacyDomain = "com.mlnavigator.term-web"
    static let migrationKey = "brandingMigrationVersion"
    static let keys = [
        "refreshInterval", "showHiddenServers", "probeHTTP", "terminalBundleID", "schemaVersion",
        IgnoreConfiguration.PreferenceKey.hideSystemExecutables,
        IgnoreConfiguration.PreferenceKey.hideRootCwdDaemons,
        IgnoreConfiguration.PreferenceKey.hideAppHelpers,
        IgnoreConfiguration.PreferenceKey.processNames,
        IgnoreConfiguration.PreferenceKey.ports,
    ]

    public static func applicationDefaults() -> UserDefaults {
        let current = UserDefaults(suiteName: IgnoreConfiguration.preferencesDomain) ?? .standard
        if let legacy = UserDefaults(suiteName: legacyDomain) {
            migrate(from: legacy, into: current)
        }
        return current
    }

    public static func migrate(from legacy: UserDefaults, into current: UserDefaults) {
        guard current.integer(forKey: migrationKey) < 1 else { return }
        for key in keys where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { current.set(value, forKey: key) }
        }
        current.set(1, forKey: migrationKey)
    }

    /// CLI/MCP reads stay read-only, including before the renamed app first launches.
    static func savedValue(_ key: String, domain: String) -> Any? {
        if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) { return value }
        guard domain == IgnoreConfiguration.preferencesDomain,
              CFPreferencesCopyAppValue(migrationKey as CFString, domain as CFString) == nil
        else { return nil }
        return CFPreferencesCopyAppValue(key as CFString, legacyDomain as CFString)
    }
}
