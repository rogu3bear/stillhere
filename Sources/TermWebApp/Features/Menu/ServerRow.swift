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
            subtitle
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(agentHelp)
            if let title = probe?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Project · branch · agent · process · uptime; the agent turns orange once orphaned.
    private var subtitle: Text {
        var leading: [String] = []
        if let project = entry.project { leading.append(project.displayName) }
        if let git = entry.git { leading.append(git.worktree == nil ? git.headDescription : "\(git.headDescription) (worktree)") }
        var trailing = ["\(entry.processName) \(entry.rootPID)"]
        if let uptime = entry.uptime(at: model.now()) { trailing.append(UptimeFormatter.string(from: uptime)) }

        guard let agent = entry.agent else { return Text((leading + trailing).joined(separator: " · ")) }
        let agentText = agent.isOrphaned
            ? Text("\(agent.kind.displayName) · orphaned").foregroundStyle(.orange)
            : Text(agent.kind.displayName)
        let before = leading.isEmpty ? Text("") : Text(leading.joined(separator: " · ") + " · ")
        return before + agentText + Text(" · " + trailing.joined(separator: " · "))
    }

    private var agentHelp: String {
        guard let agent = entry.agent else { return "" }
        let name = agent.kind.displayName
        return agent.isOrphaned
            ? "Started by \(name); that session has ended, so nothing will stop this server for you."
            : "Started by \(name)."
    }
}
