import Foundation
import SwiftUI

/// Row actions that hand off to other apps. Injected through the environment so previews
/// and tests never open windows or touch the pasteboard.
protocol ServerActions: Sendable {
    func open(_ url: URL)
    func copy(_ url: URL)
    func reveal(_ folder: URL)
    func openInTerminal(_ folder: URL)
}

/// Does nothing: for previews.
struct InertServerActions: ServerActions {
    func open(_ url: URL) {}
    func copy(_ url: URL) {}
    func reveal(_ folder: URL) {}
    func openInTerminal(_ folder: URL) {}
}

extension EnvironmentValues {
    @Entry var serverActions: any ServerActions = InertServerActions()
}
