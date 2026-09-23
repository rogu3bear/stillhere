import SwiftUI
import TermWebCore

/// Open, Copy URL, Reveal in Finder, Open in Terminal, Stop.
struct ServerRowActions: View {
    let entry: ServerEntry

    @Environment(ServerListModel.self) private var model
    @Environment(\.serverActions) private var actions
    @State private var copied = false

    var body: some View {
        let folder = entry.project?.projectRoot
        HStack(spacing: 6) {
            Button("Open", systemImage: "safari") { actions.open(entry.displayURL) }
                .help("Open in the default browser")
            Button(copied ? "Copied" : "Copy URL", systemImage: copied ? "checkmark" : "doc.on.doc") {
                actions.copy(entry.displayURL)
                copied = true
            }
            .help("Copy \(entry.displayURL.absoluteString)")
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
            Button("Finder", systemImage: "folder") { folder.map(actions.reveal) }
                .disabled(folder == nil)
                .help("Reveal the project folder in Finder")
            Button("Terminal", systemImage: "terminal") { folder.map(actions.openInTerminal) }
                .disabled(folder == nil)
                .help("Open the project folder in Terminal")
            Spacer(minLength: 0)
            Button("Stop", systemImage: "stop.circle", role: .destructive) {
                model.stopFlow.requestStop(entry)
            }
            .disabled(model.stopFlow.phase(for: entry.port) != nil)
            .help("Stop this server (SIGTERM, after confirmation)")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
