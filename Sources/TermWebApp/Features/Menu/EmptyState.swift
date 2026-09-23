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
                Text(hiddenCount == 1
                     ? "1 system listener is hidden. Show it in Settings."
                     : "\(hiddenCount) system listeners are hidden. Show them in Settings.")
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
