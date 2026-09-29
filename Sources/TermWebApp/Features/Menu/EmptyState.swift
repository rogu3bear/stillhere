import SwiftUI

struct EmptyState: View {
    let hiddenCount: Int
    let showingHidden: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No dev servers running")
                .font(.callout)
            if hiddenCount > 0, !showingHidden {
                // Hidden rows include ignored names and database ports, not only system processes.
                Text(hiddenCount == 1
                     ? "1 listener is hidden. Show it in Settings."
                     : "\(hiddenCount) listeners are hidden. Show them in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }
}
