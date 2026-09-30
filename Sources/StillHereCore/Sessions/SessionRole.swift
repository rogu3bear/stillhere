import Foundation

/// Whether a session can change the working tree. Only writers can collide: a reviewer
/// sharing a checkout with a writer is expected, not a hazard.
public enum SessionRole: Sendable, Hashable, Codable {
    case writer
    /// Launched for review or with edits disabled; `reason` says how that was decided.
    case reviewer(reason: String)

    public var isWriter: Bool { self == .writer }

    public var label: String {
        switch self {
        case .writer: "writer"
        case .reviewer: "reviewer"
        }
    }
}

/// Derives a session's role from its agent process's argv. Only explicit launch signals
/// count; anything else is a writer, so a real collision is never hidden by guessing.
/// The argv (which can contain prompts) is inspected here and never stored or reported.
public enum SessionRoleClassifier {
    /// Known review launchers, matched on a `--settings` file path.
    static let reviewSettingsSuffixes: [(suffix: String, reason: String)] = [
        ("/iTerm.app/Contents/Resources/code-review-settings.txt", "iTerm2 code review"),
    ]

    public static func role(argv: [String]) -> SessionRole {
        let arguments = Array(argv.dropFirst())
        for (index, argument) in arguments.enumerated() {
            let (flag, inline) = split(argument)
            func value() -> String? { inline ?? (index + 1 < arguments.count ? arguments[index + 1] : nil) }
            switch flag {
            case "--settings":
                if let path = value(), let known = reviewSettingsSuffixes.first(where: { path.hasSuffix($0.suffix) }) {
                    return .reviewer(reason: known.reason)
                }
            case "--permission-mode":
                if value() == "plan" { return .reviewer(reason: "plan mode") }
            case "--disallowedTools", "--disallowed-tools":
                // Values run until the next flag: `--disallowedTools Edit Write` or "Edit,Write".
                let values = inline.map { [$0] } ?? Array(arguments.dropFirst(index + 1).prefix { !$0.hasPrefix("-") })
                let tools = Set(values.flatMap { $0.split(whereSeparator: { $0 == "," || $0 == " " }) }
                    .map { $0.split(separator: "(").first.map(String.init) ?? "" })
                if tools.contains("Edit") && tools.contains("Write") { return .reviewer(reason: "edits disallowed") }
            case "-s", "--sandbox":
                if value() == "read-only" { return .reviewer(reason: "read-only sandbox") }
            default:
                break
            }
        }
        return .writer
    }

    private static func split(_ argument: String) -> (String, String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else { return (argument, nil) }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }
}
