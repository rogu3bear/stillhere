import SwiftUI

/// Menu bar item: an icon and the number of visible servers. Menu bar labels render only
/// text and images, so this stays a plain `Label`.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        Label("\(count)", systemImage: "server.rack")
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(count == 1 ? "1 dev server running" : "\(count) dev servers running")
    }
}
