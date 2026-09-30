import SwiftUI
import StillHereCore

/// Small capsule naming the detected framework or runtime.
struct FrameworkBadge: View {
    let guess: FrameworkGuess

    var body: some View {
        Label(guess.name, systemImage: guess.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(guess.source == .runtime ? 0.08 : 0.16), in: .capsule)
            .foregroundStyle(guess.source == .runtime ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .help(helpText)
    }

    private var helpText: String {
        switch guess.source {
        case .argv: "Detected from the command line"
        case .manifest: "Detected from the project manifest"
        case .header: "Detected from HTTP response headers"
        case .runtime: "Runtime only; no framework detected"
        }
    }
}
