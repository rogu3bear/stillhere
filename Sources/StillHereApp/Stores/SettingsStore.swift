import Foundation
import Observation
import StillHereCore

/// The single owner of user preferences, backed by an injected `UserDefaults`.
/// Views bind to this store rather than to `@AppStorage`, so the model and the views
/// never disagree. Launch at login is deliberately absent: the system owns that state.
@Observable
final class SettingsStore {
    enum Key {
        static let refreshInterval = "refreshInterval"
        static let showHiddenServers = "showHiddenServers"
        static let probeHTTP = "probeHTTP"
        static let terminalBundleID = "terminalBundleID"
        // Shared with the CLI and MCP server, which read the saved ignore list.
        static let hideSystemExecutables = IgnoreConfiguration.PreferenceKey.hideSystemExecutables
        static let hideRootCwdDaemons = IgnoreConfiguration.PreferenceKey.hideRootCwdDaemons
        static let hideAppHelpers = IgnoreConfiguration.PreferenceKey.hideAppHelpers
        static let processNames = IgnoreConfiguration.PreferenceKey.processNames
        static let ports = IgnoreConfiguration.PreferenceKey.ports
        static let schemaVersion = "schemaVersion"
    }

    static let refreshIntervals: [Double] = [2, 3, 5, 10, 30]
    static let defaultRefreshInterval: Double = 5
    static let schemaVersion = 1

    @ObservationIgnored private let defaults: UserDefaults

    var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }
    var showHiddenServers: Bool {
        didSet { defaults.set(showHiddenServers, forKey: Key.showHiddenServers) }
    }
    var probeHTTP: Bool {
        didSet { defaults.set(probeHTTP, forKey: Key.probeHTTP) }
    }
    /// Installed terminals, looked up at launch and when Settings opens.
    private(set) var installedTerminals: [TerminalApp]
    /// nil means Automatic (see `TerminalApp.resolve`).
    var terminalBundleID: String? {
        didSet { defaults.set(terminalBundleID, forKey: Key.terminalBundleID) }
    }
    var hideSystemExecutables: Bool {
        didSet { defaults.set(hideSystemExecutables, forKey: Key.hideSystemExecutables) }
    }
    var hideRootCwdDaemons: Bool {
        didSet { defaults.set(hideRootCwdDaemons, forKey: Key.hideRootCwdDaemons) }
    }
    var hideAppHelpers: Bool {
        didSet { defaults.set(hideAppHelpers, forKey: Key.hideAppHelpers) }
    }
    private(set) var processNames: [String] {
        didSet { defaults.set(processNames, forKey: Key.processNames) }
    }
    private(set) var ports: [Int] {
        didSet { defaults.set(ports, forKey: Key.ports) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Key.refreshInterval) as? Double
        refreshInterval = stored.flatMap { Self.refreshIntervals.contains($0) ? $0 : nil }
            ?? Self.defaultRefreshInterval
        showHiddenServers = defaults.object(forKey: Key.showHiddenServers) as? Bool ?? false
        probeHTTP = defaults.object(forKey: Key.probeHTTP) as? Bool ?? true
        terminalBundleID = defaults.string(forKey: Key.terminalBundleID)
        installedTerminals = TerminalApp.findInstalled()
        let saved = IgnoreConfiguration(stored: { defaults.object(forKey: $0) })
        hideSystemExecutables = saved.hideSystemExecutables
        hideRootCwdDaemons = saved.hideRootCwdDaemons
        hideAppHelpers = saved.hideAppHelpers
        processNames = saved.processNames
        ports = saved.ports
        defaults.set(Self.schemaVersion, forKey: Key.schemaVersion)
    }

    var terminal: TerminalApp { TerminalApp.resolve(preferred: terminalBundleID, among: installedTerminals) }

    /// What Automatic resolves to.
    var automaticTerminal: TerminalApp { TerminalApp.resolve(preferred: nil, among: installedTerminals) }

    func refreshInstalledTerminals() {
        let found = TerminalApp.findInstalled()
        if found != installedTerminals { installedTerminals = found }
    }

    /// The rules the detector classifies with.
    var ignoreConfiguration: IgnoreConfiguration {
        IgnoreConfiguration(
            hideSystemExecutables: hideSystemExecutables,
            hideRootCwdDaemons: hideRootCwdDaemons,
            hideAppHelpers: hideAppHelpers,
            processNames: processNames,
            ports: ports
        )
    }

    /// Adds a trimmed name unless it is empty or already listed (case-insensitive).
    /// Returns false when nothing was added.
    @discardableResult
    func addProcessName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !processNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return false }
        processNames.append(name)
        return true
    }

    func removeProcessName(_ name: String) {
        processNames.removeAll { $0 == name }
    }

    /// Adds a TCP port in 1...65535 unless already listed. Returns false when nothing was added.
    @discardableResult
    func addPort(_ raw: String) -> Bool {
        guard let port = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port), !ports.contains(port)
        else { return false }
        ports.append(port)
        ports.sort()
        return true
    }

    func removePort(_ port: Int) {
        ports.removeAll { $0 == port }
    }

    /// Restores every ignore rule to its default. Other preferences are untouched.
    func resetIgnoreList() {
        let base = IgnoreConfiguration.defaults
        hideSystemExecutables = base.hideSystemExecutables
        hideRootCwdDaemons = base.hideRootCwdDaemons
        hideAppHelpers = base.hideAppHelpers
        processNames = base.processNames
        ports = base.ports
    }
}
