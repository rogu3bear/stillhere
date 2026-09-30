/// Why a listener is hidden from the default list.
public enum HiddenReason: Sendable, Hashable {
    case system
    case daemon
    case appHelper
    case ignoredName(String)
    case databasePort(Int)

    /// Structural reasons (not user ignore rules): processes the user did not start as a
    /// dev server, which must never be signalled from the menu.
    public var isProtected: Bool {
        switch self {
        case .system, .daemon, .appHelper: true
        case .ignoredName, .databasePort: false
        }
    }

    public var label: String {
        switch self {
        case .system: "System"
        case .daemon: "Daemon"
        case .appHelper: "App helper"
        case .ignoredName(let name): "Ignored: \(name)"
        case .databasePort(let port): "Database port \(port)"
        }
    }
}
