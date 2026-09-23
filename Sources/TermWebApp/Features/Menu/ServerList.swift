import SwiftUI

/// Visible rows, then (when enabled) hidden rows. Rows are identified by port, so row
/// state survives refreshes. The list scrolls once it exceeds `maxHeight`.
struct ServerList: View {
    @Environment(ServerListModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var contentHeight: CGFloat = 0

    private let maxHeight: CGFloat = 480

    var body: some View {
        ScrollView {
            rows
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            let visible = model.visibleServers
            if visible.isEmpty {
                EmptyState(hiddenCount: model.hiddenServers.count, showingHidden: settings.showHiddenServers)
            }
            ForEach(visible) { entry in
                ServerRow(entry: entry)
            }
            let hidden = model.hiddenServers
            if settings.showHiddenServers, !hidden.isEmpty {
                Text("Hidden")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(hidden) { entry in
                    ServerRow(entry: entry)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
