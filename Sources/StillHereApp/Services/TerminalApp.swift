import AppKit

/// Terminal apps that open a new window at a folder handed to them by Launch Services.
struct TerminalApp: Hashable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    static let appleTerminal = TerminalApp(bundleID: "com.apple.Terminal", name: "Terminal")

    /// Preference order for "Automatic": a third-party terminal someone installed is the
    /// one they use; Terminal is always present.
    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        appleTerminal,
    ]

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Launch Services lookups: call when the list may have changed, not per view update.
    static func findInstalled() -> [TerminalApp] {
        known.filter { $0.applicationURL != nil }
    }

    /// The saved choice when it is still installed, otherwise the first installed terminal.
    static func resolve(preferred bundleID: String?, among available: [TerminalApp]) -> TerminalApp {
        if let bundleID, let match = available.first(where: { $0.bundleID == bundleID }) {
            return match
        }
        return available.first ?? appleTerminal
    }
}
