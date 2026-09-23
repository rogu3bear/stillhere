import Foundation

/// An agent session as the CLI and MCP server report it.
public struct SessionReport: Sendable, Hashable, Encodable {
    public var pid: Int32
    public var agent: String
    public var kind: String
    public var startedAt: Date
    public var uptimeSeconds: Int
    public var checkouts: [GitContext]
    public var parentSessionPID: Int32?
    /// "writer" or "reviewer".
    public var role: String
    /// Why a reviewer was classified as one; nil for writers.
    public var roleReason: String?
    /// Ports of servers this session started.
    public var servers: [Int]
    /// Checkout roots this session shares with another independent session.
    public var collidesIn: [String]

    public init(session: AgentSession, servers: [ServerEntry], collisions: [SessionCollision], now: Date) {
        pid = session.pid
        agent = session.kind.displayName
        kind = session.kind.slug
        startedAt = session.startTime
        uptimeSeconds = max(0, Int(now.timeIntervalSince(session.startTime)))
        checkouts = session.checkouts
        parentSessionPID = session.parentSessionPID
        role = session.role.label
        if case .reviewer(let reason) = session.role { roleReason = reason } else { roleReason = nil }
        self.servers = Array(Set(servers.filter(session.owns).map(\.port))).sorted()
        collidesIn = collisions.filter { $0.sessionPIDs.contains(session.pid) }.map(\.checkout.checkoutRoot)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)
        try container.encode(agent, forKey: .agent)
        try container.encode(kind, forKey: .kind)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(checkouts, forKey: .checkouts)
        try container.encode(parentSessionPID, forKey: .parentSessionPID)
        try container.encode(role, forKey: .role)
        try container.encode(roleReason, forKey: .roleReason)
        try container.encode(servers, forKey: .servers)
        try container.encode(collidesIn, forKey: .collidesIn)
    }

    private enum CodingKeys: String, CodingKey {
        case pid, agent, kind, startedAt, uptimeSeconds, checkouts, parentSessionPID, role, roleReason, servers, collidesIn
    }
}

/// Sessions, their collisions and the servers they started, from one scan.
public struct SessionOverview: Sendable, Hashable {
    public var sessions: [AgentSession]
    public var collisions: [SessionCollision]

    public init(sessions: [AgentSession], now: Date = Date(), caller: Int32? = nil) {
        self.sessions = sessions
        collisions = SessionScanner.collisions(sessions, now: now, alwaysEligible: caller)
    }

    public static let empty = SessionOverview(sessions: [])

    /// Sessions working in at least one checkout.
    public var active: [AgentSession] { sessions.filter { !$0.isIdle } }

    /// Active sessions for display: colliding top-level sessions first, then by checkout
    /// name; each followed by its workers (with their nesting depth).
    public var displayOrder: [(session: AgentSession, depth: Int)] {
        let active = active
        let activePIDs = Set(active.map(\.pid))
        let colliding = Set(collisions.flatMap(\.sessionPIDs))
        func sortKey(_ session: AgentSession) -> (Int, String, Int32) {
            (colliding.contains(session.pid) ? 0 : 1, session.checkouts.first?.checkoutRoot ?? "", session.pid)
        }
        let children = Dictionary(grouping: active.filter { $0.parentSessionPID.map(activePIDs.contains) == true },
                                  by: { $0.parentSessionPID! })
        var result: [(AgentSession, Int)] = []
        func visit(_ session: AgentSession, depth: Int) {
            result.append((session, depth))
            for child in (children[session.pid] ?? []).sorted(by: { sortKey($0) < sortKey($1) }) {
                visit(child, depth: depth + 1)
            }
        }
        for root in active.filter({ $0.parentSessionPID.map(activePIDs.contains) != true }).sorted(by: { sortKey($0) < sortKey($1) }) {
            visit(root, depth: 0)
        }
        return result
    }

    /// Other independent sessions sharing a checkout with `session`.
    public func collisionPartners(of session: AgentSession) -> [Int32] {
        let pids = collisions.filter { $0.sessionPIDs.contains(session.pid) }
            .flatMap(\.sessionPIDs).filter { $0 != session.pid }
        return Array(Set(pids)).sorted() // a partner sharing several checkouts is listed once
    }

    public func reports(servers: [ServerEntry], includeIdle: Bool, now: Date = Date()) -> [SessionReport] {
        sessions
            .filter { includeIdle || !$0.isIdle }
            .map { SessionReport(session: $0, servers: servers, collisions: collisions, now: now) }
    }
}
