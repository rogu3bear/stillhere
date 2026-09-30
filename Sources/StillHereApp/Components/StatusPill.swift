import SwiftUI
import StillHereCore

/// HTTP status (or the hidden reason) at the trailing edge of a row.
struct StatusPill: View {
    let probe: ProbeResult?
    let hiddenReason: HiddenReason?

    var body: some View {
        if let hiddenReason {
            pill(hiddenReason.label, color: .gray)
        } else if let probe {
            if let status = probe.status {
                pill("\(status)", color: color(for: status))
                    .help(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)
            } else if probe.failure != nil {
                pill("No HTTP", color: .gray)
            }
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private func color(for status: Int) -> Color {
        switch status {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        default: .red
        }
    }
}
