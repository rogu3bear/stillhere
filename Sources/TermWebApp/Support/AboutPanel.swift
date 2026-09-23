import AppKit

/// The standard About panel; it reads the name, version and icon from Info.plist.
enum AboutPanel {
    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Lists local dev servers. No network access beyond localhost, no telemetry."),
        ])
    }
}
