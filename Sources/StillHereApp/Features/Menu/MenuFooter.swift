import AppKit
import SwiftUI

/// Settings, About and Quit.
struct MenuFooter: View {
    var body: some View {
        HStack(spacing: 12) {
            OpenSettingsButton()
            Spacer()
            Button("About Still Here") { AboutPanel.show() }
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .help("Quit Still Here (⌘Q)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
