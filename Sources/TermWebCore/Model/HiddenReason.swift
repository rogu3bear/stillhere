/// Why a listener is hidden from the default list.
public enum HiddenReason: Sendable, Hashable {
    case system
    case daemon
    case appHelper
    case ignoredName(String)
    case databasePort(Int)

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
