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
        try container.encode(servers, forKey: .servers)
        try container.encode(collidesIn, forKey: .collidesIn)
    }

    private enum CodingKeys: String, CodingKey {
        case pid, agent, kind, startedAt, uptimeSeconds, checkouts, parentSessionPID, servers, collidesIn
    }
}

/// Sessions, their collisions and the servers they started, from one scan.
public struct SessionOverview: Sendable {
    public var sessions: [AgentSession]
    public var collisions: [SessionCollision]

    public init(sessions: [AgentSession]) {
        self.sessions = sessions
        collisions = SessionScanner.collisions(sessions)
    }

    public func reports(servers: [ServerEntry], includeIdle: Bool, now: Date = Date()) -> [SessionReport] {
        sessions
            .filter { includeIdle || !$0.isIdle }
            .map { SessionReport(session: $0, servers: servers, collisions: collisions, now: now) }
    }
}
