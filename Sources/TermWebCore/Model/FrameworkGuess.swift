/// A best guess at what kind of server a process is.
public struct FrameworkGuess: Sendable, Hashable {
    /// Which signal produced the guess, strongest first.
    public enum Source: String, Sendable, Hashable {
        case argv
        case manifest
        case header
        case runtime
    }

    public var name: String
    public var source: Source

    public init(name: String, source: Source) {
        self.name = name
        self.source = source
    }

    /// SF Symbol used by the UI badge.
    public var symbolName: String {
        switch source {
        case .argv, .manifest, .header: "shippingbox"
        case .runtime: "terminal"
        }
    }
}
