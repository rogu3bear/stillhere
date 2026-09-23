import SwiftUI

/// Server count, refresh control and the last scan error.
struct MenuHeader: View {
    @Environment(ServerListModel.self) private var model
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                if model.collisionCount > 0 {
                    Text(model.collisionCount == 1 ? "1 collision" : "\(model.collisionCount) collisions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .help("Independent agent sessions are working in the same checkout")
                }
                if model.orphanCount > 0 {
                    Text("\(model.orphanCount) orphaned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .help("Started by coding agent sessions that have ended")
                }
                if !settings.showHiddenServers, !model.hiddenServers.isEmpty {
                    Text("\(model.hiddenServers.count) hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .opacity(model.isRefreshing ? 1 : 0)
                    .accessibilityHidden(!model.isRefreshing)
                Button {
                    Task { await model.refresh(.manual) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")
                .accessibilityLabel("Refresh")
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var title: String {
        let count = model.visibleCount
        return count == 1 ? "1 dev server" : "\(count) dev servers"
    }
}
