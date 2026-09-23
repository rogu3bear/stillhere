import SwiftUI
import TermWebCore

/// Expanded facts about one server: URL, process, folder, uptime, bindings and HTTP.
struct ServerRowDetails: View {
    let entry: ServerEntry
    let probe: ProbeResult?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            row("URL") {
                Text(entry.displayURL.absoluteString).textSelection(.enabled)
            }
            row("Process") {
                Text(processText).textSelection(.enabled)
            }
            row("Folder") {
                if let project = entry.project {
                    Text(project.displayName)
                        .help(project.fullPath)
                        .accessibilityValue(project.fullPath)
                } else {
                    Text("Unknown").foregroundStyle(.secondary)
                }
            }
            row("Uptime") {
                if let start = entry.process?.startTime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(UptimeFormatter.string(from: max(0, context.date.timeIntervalSince(start))))
                            .monospacedDigit()
                    }
                } else {
                    Text("Unknown").foregroundStyle(.secondary)
                }
            }
            row("Listening") {
                Text(entry.bindings.map { "\($0.address.displayText) (\($0.family == .ipv4 ? "IPv4" : "IPv6"))" }
                    .joined(separator: ", "))
            }
            row("HTTP") {
                Text(httpText)
            }
            if let reason = entry.hiddenReason {
                row("Hidden") { Text(reason.label) }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var processText: String {
        var text = "\(entry.processName) (PID \(entry.rootPID))"
        if !entry.workerPIDs.isEmpty {
            text += ", workers " + entry.workerPIDs.map(String.init).joined(separator: ", ")
        }
        return text
    }

    private var httpText: String {
        guard let probe else { return "Not checked" }
        if let failure = probe.failure {
            return switch failure {
            case .refused: "Connection refused"
            case .timedOut: "Timed out"
            case .other(let code): "Error \(code)"
            }
        }
        var parts: [String] = []
        if let status = probe.status {
            parts.append("\(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)")
        }
        if let location = probe.location { parts.append("→ \(location)") }
        if let server = probe.serverHeader ?? probe.poweredBy { parts.append(server) }
        let milliseconds = Int((probe.latency.timeInterval * 1000).rounded())
        parts.append("\(milliseconds) ms via \(probe.host)")
        return parts.joined(separator: " · ")
    }
}
