import Foundation

/// Where the UI gets agent sessions; swappable for previews and tests.
public protocol SessionSource: Sendable {
    func sessions() async -> [AgentSession]
}

/// Scans the live process table off the caller's actor (about 10 ms for ~800 processes).
public struct LiveSessionSource: SessionSource {
    public init() {}

    @concurrent
    public func sessions() async -> [AgentSession] {
        SessionScanner().scan()
    }
}

/// Fixed sessions.
public struct FakeSessionSource: SessionSource {
    public var fixed: [AgentSession]

    public init(_ sessions: [AgentSession] = SampleSessions.all) {
        fixed = sessions
    }

    public func sessions() async -> [AgentSession] { fixed }
}

/// Deterministic sessions matching `SampleServers`: the Claude Code session that started
/// the Vite server shares its checkout with an independent Codex session.
public enum SampleSessions {
    static let shop = GitContext(checkoutRoot: "/Users/dev/Projects/shop", branch: "feat/cart")

    public static let claude = AgentSession(
        pid: 40_900, kind: .claudeCode, startTime: SampleServers.referenceDate.addingTimeInterval(-2_400),
        cwd: shop.checkoutRoot, ownCheckout: shop, checkouts: [shop]
    )
    public static let codex = AgentSession(
        pid: 42_000, kind: .codex, startTime: SampleServers.referenceDate.addingTimeInterval(-600),
        cwd: "/", checkouts: [shop]
    )
    public static let all = [claude, codex]
}
