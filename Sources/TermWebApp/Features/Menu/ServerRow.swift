import SwiftUI
import TermWebCore

/// One server. The summary is always shown; clicking it toggles the details and actions.
/// Expansion is row `@State` under the port identity, so it survives refreshes.
struct ServerRow: View {
    let entry: ServerEntry

    @Environment(ServerListModel.self) private var model
    @Environment(\.serverActions) private var actions
    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        let probe = model.probe(for: entry)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                summary(probe: probe)
                    .contentShape(.rect)
                    .onTapGesture { toggle() }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(isExpanded ? "Hides details" : "Shows details and actions")
                    .accessibilityAction { toggle() }
                Button {
                    actions.open(model.url(for: entry))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("Open \(model.url(for: entry).absoluteString)")
                .accessibilityLabel("Open in browser")
            }
            if let phase = model.stopFlow.phase(for: entry) {
                StopConfirmationBar(entry: entry, phase: phase)
            }
            if isExpanded {
                ServerRowDetails(entry: entry, probe: probe)
                ServerRowActions(entry: entry)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(isHovering || isExpanded ? 0.6 : 0), in: .rect(cornerRadius: 8))
        .padding(.horizontal, 4)
        .onHover { isHovering = $0 }
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
    }

    private func summary(probe: ProbeResult?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: "localhost:\(entry.port)")
                    .font(.body.monospacedDigit().weight(.semibold))
                FrameworkBadge(guess: model.framework(for: entry))
                Spacer(minLength: 4)
                StatusPill(probe: probe, hiddenReason: entry.hiddenReason)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let title = probe?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let project = entry.project { parts.append(project.displayName) }
        parts.append("\(entry.processName) \(entry.rootPID)")
        if let uptime = entry.uptime(at: model.now()) { parts.append(UptimeFormatter.string(from: uptime)) }
        return parts.joined(separator: " · ")
    }
}
