import Foundation

/// A running coding-agent session: an agent's root process and the checkouts it and its
/// descendants are working in.
public struct AgentSession: Sendable, Hashable, Identifiable {
    public var pid: Int32
    public var kind: AgentContext.Kind
    public var startTime: Date
    /// The agent process's own working directory ("/" for app-hosted agents like the
    /// Codex app server, whose threads work in child processes).
    public var cwd: String?
    /// The checkout of the session's own working directory; nil when that directory is /,
    /// home or not in a checkout, even if descendants work in one.
    public var ownCheckout: GitContext?
    /// Checkouts the session is working in: its own, plus those of recently started
    /// descendants (see `SessionScanner.recentWindow`), excluding nested sessions.
    public var checkouts: [GitContext]
    /// The agent session that started this one (a delegated worker), if any.
    public var parentSessionPID: Int32?
    /// The root and its descendants, excluding nested sessions.
    public var memberPIDs: Set<Int32>

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        kind: AgentContext.Kind,
        startTime: Date,
        cwd: String? = nil,
        ownCheckout: GitContext? = nil,
        checkouts: [GitContext] = [],
        parentSessionPID: Int32? = nil,
        memberPIDs: Set<Int32> = []
    ) {
        self.pid = pid
        self.kind = kind
        self.startTime = startTime
        self.cwd = cwd
        self.ownCheckout = ownCheckout
        self.checkouts = checkouts
        self.parentSessionPID = parentSessionPID
        self.memberPIDs = memberPIDs.union([pid])
    }

    /// Servers this session started: attributed to it by environment, or running under it.
    public func owns(_ server: ServerEntry) -> Bool {
        server.agent?.launcherPID == pid || memberPIDs.contains(server.rootPID)
    }

    public var isIdle: Bool { checkouts.isEmpty }

    // Equality leaves out `memberPIDs`: short-lived tool processes change it on nearly every
    // scan, and nothing displayed depends on it directly.
    public static func == (lhs: AgentSession, rhs: AgentSession) -> Bool {
        lhs.pid == rhs.pid && lhs.kind == rhs.kind && lhs.startTime == rhs.startTime && lhs.cwd == rhs.cwd
            && lhs.ownCheckout == rhs.ownCheckout && lhs.checkouts == rhs.checkouts
            && lhs.parentSessionPID == rhs.parentSessionPID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(startTime)
    }
}

/// Two or more independent sessions in one checkout. Sessions that started one another
/// (supervisor and worker) are not a collision.
public struct SessionCollision: Sendable, Hashable, Identifiable {
    public var checkout: GitContext
    public var sessionPIDs: [Int32]

    public var id: String { checkout.checkoutRoot }

    public init(checkout: GitContext, sessionPIDs: [Int32]) {
        self.checkout = checkout
        self.sessionPIDs = sessionPIDs
    }
}
