import AppKit

/// NSWorkspace / NSPasteboard implementation. No Apple Events, so no automation
/// permission or entitlement is needed.
struct LiveServerActions: ServerActions {
    static let terminalBundleID = "com.apple.Terminal"
    static let terminalFallback = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    func reveal(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Opens a new Terminal window at `folder`.
    func openInTerminal(_ folder: URL) {
        let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.terminalBundleID)
            ?? Self.terminalFallback
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
