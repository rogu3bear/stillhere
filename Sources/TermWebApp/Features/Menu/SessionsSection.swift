import SwiftUI
import TermWebCore

/// Agent sessions working in git checkouts, above the servers. Sessions that share a
/// checkout with another independent session are orange.
struct SessionsSection: View {
    @Environment(ServerListModel.self) private var model

    var body: some View {
        let overview = model.sessionOverview
        let ordered = overview.displayOrder
        if !ordered.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                ForEach(ordered, id: \.session.pid) { item in
                    SessionRow(session: item.session, partners: overview.collisionPartners(of: item.session))
                        .padding(.leading, CGFloat(min(item.depth, 3)) * 14)
                }
            }
            .padding(.bottom, 4)
            Divider()
        }
    }
}

struct SessionRow: View {
    let session: AgentSession
    let partners: [Int32]

    @Environment(ServerListModel.self) private var model

    var body: some View {
        let colliding = !partners.isEmpty
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: colliding ? "exclamationmark.triangle.fill" : session.role.isWriter ? "sparkles" : "eye")
                    .foregroundStyle(colliding ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .imageScale(.small)
                Text(session.kind.displayName).font(.callout.weight(.medium))
                Text(checkoutText).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(UptimeFormatter.string(from: model.now().timeIntervalSince(session.startTime)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                // The branch gives way first; the collision partner or PID always stays whole.
                Text(branchText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                Text(" · " + detailText)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .font(.caption)
            .foregroundStyle(colliding ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .padding(.leading, 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var checkoutText: String {
        session.checkouts.map { URL(fileURLWithPath: $0.checkoutRoot).lastPathComponent }.joined(separator: ", ")
    }

    private var branchText: String {
        session.checkouts.map(\.headDescription).joined(separator: ", ")
    }

    private var detailText: String {
        var parts: [String] = []
        if case .reviewer(let reason) = session.role {
            parts.append("reviewing (\(reason))")
        } else if !partners.isEmpty {
            parts.append("shared with PID " + partners.map(String.init).joined(separator: ", "))
        } else if let parent = session.parentSessionPID {
            parts.append("worker of PID \(parent)")
        } else {
            parts.append("PID \(session.pid)")
        }
        let servers = model.servers.filter(session.owns).count
        if servers > 0 { parts.append(servers == 1 ? "1 server" : "\(servers) servers") }
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        let paths = session.checkouts.map(\.checkoutRoot).joined(separator: "\n")
        guard !partners.isEmpty else { return paths }
        return paths + "\nAnother independent agent session is working in this checkout; their edits can collide."
    }
}
