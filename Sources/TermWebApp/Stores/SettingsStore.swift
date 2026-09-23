import Foundation
import Observation
import TermWebCore

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
        static let hideSystemExecutables = "ignore.hideSystemExecutables"
        static let hideRootCwdDaemons = "ignore.hideRootCwdDaemons"
        static let hideAppHelpers = "ignore.hideAppHelpers"
        static let processNames = "ignore.processNames"
        static let ports = "ignore.ports"
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
        let base = IgnoreConfiguration.defaults
        hideSystemExecutables = defaults.object(forKey: Key.hideSystemExecutables) as? Bool ?? base.hideSystemExecutables
        hideRootCwdDaemons = defaults.object(forKey: Key.hideRootCwdDaemons) as? Bool ?? base.hideRootCwdDaemons
        hideAppHelpers = defaults.object(forKey: Key.hideAppHelpers) as? Bool ?? base.hideAppHelpers
        processNames = defaults.stringArray(forKey: Key.processNames) ?? base.processNames
        ports = defaults.array(forKey: Key.ports) as? [Int] ?? base.ports
        defaults.set(Self.schemaVersion, forKey: Key.schemaVersion)
    }

    var terminal: TerminalApp { TerminalApp.resolve(preferred: terminalBundleID) }

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
