import AppKit
import SwiftUI

/// Opens the Settings scene. A menu-bar-only (UIElement) app is not active when the panel
/// is clicked, so activate first or the window can open behind other apps.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}
