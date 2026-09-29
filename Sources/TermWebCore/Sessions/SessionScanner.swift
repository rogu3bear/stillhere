import Foundation

/// Finds agent sessions in a process table and the checkouts they work in. Pure given its
/// inputs; `scan()` wires in libproc and `.git` reads.
///
/// "Working in" is deliberately narrow, because a collision warning asks the user to act:
/// a session works in the checkout of its own working directory, plus the checkouts of
/// descendants started within `recentWindow` (the commands it is running now). Long-lived
/// descendants such as a dev server or an MCP helper started hours ago don't count; the
/// menu still links servers to their session through `memberPIDs`. Neither do helpers
/// shipped in the agent's own app bundle: the Codex app server starts a REPL in each
/// thread's directory, including threads CCodex hands to Claude Code.
public struct SessionScanner: Sendable {
    public static let recentWindow: TimeInterval = 10 * 60
    /// Sessions younger than this don't count toward a collision (except the caller's own),
    /// which ignores one-shot invocations such as `claude --version`.
    public static let minimumCollisionAge: TimeInterval = 5

    public init() {}

    /// Live scan of the current user's processes.
    public func scan(home: String = NSHomeDirectory(), now: Date = Date()) -> [AgentSession] {
        var gitCache: [String: GitContext?] = [:]
        return Self.sessions(
            in: .snapshot(),
            cwd: Libproc.currentDirectory,
            checkout: { directory in
                if let cached = gitCache[directory] { return cached }
                let context = GitReader.context(for: directory, home: home)
                gitCache[directory] = context
                return context
            },
            home: home,
            now: now
        )
    }

    public static func isAgentRoot(_ record: ProcessRecord) -> Bool {
        record.agentKind != nil
    }

    /// The agent session a process runs under: its nearest agent ancestor.
    public static func callerSessionPID(of pid: Int32 = getpid(), in table: ProcessTable = .snapshot()) -> Int32? {
        table.ancestors(of: pid).first(where: isAgentRoot)?.pid
    }

    public static func sessions(
        in table: ProcessTable,
        cwd: (Int32) -> String?,
        checkout: (String) -> GitContext?,
        home: String,
        now: Date
    ) -> [AgentSession] {
        let roots = table.records.values.filter(isAgentRoot).sorted { $0.pid < $1.pid }
        let wrappers = launcherWrappers(roots)
        let sessionPIDs = Set(roots.map(\.pid)).subtracting(wrappers)
        let homeRoot = URL(fileURLWithPath: home, isDirectory: true).standardized.path

        func workCheckout(_ pid: Int32) -> GitContext? {
            guard let directory = cwd(pid), isWorkDirectory(directory, home: home),
                  let context = checkout(directory),
                  // A dotfiles repo at ~ would otherwise claim every folder beneath it.
                  URL(fileURLWithPath: context.checkoutRoot, isDirectory: true).standardized.path != homeRoot
            else { return nil }
            return context
        }

        return roots.filter { sessionPIDs.contains($0.pid) }.map { root in
            let parent = table.ancestors(of: root.pid).first { sessionPIDs.contains($0.pid) }
            let descendants = table.descendants(of: root.pid) { sessionPIDs.contains($0.pid) }
            let own = workCheckout(root.pid)
            var checkouts = own.map { [$0] } ?? []
            var seen = Set(checkouts.map(\.checkoutRoot))
            for member in descendants where now.timeIntervalSince(member.startTime) <= recentWindow {
                if member.appBundle != nil, member.appBundle == root.appBundle { continue }
                guard let context = workCheckout(member.pid), seen.insert(context.checkoutRoot).inserted else { continue }
                checkouts.append(context)
            }
            return AgentSession(
                pid: root.pid,
                kind: root.agentKind ?? .other(root.name),
                startTime: root.startTime,
                cwd: cwd(root.pid),
                ownCheckout: own,
                checkouts: checkouts.sorted { $0.checkoutRoot < $1.checkoutRoot },
                parentSessionPID: parent?.pid,
                memberPIDs: Set(([root] + descendants).map(\.pid)),
                role: root.role
            )
        }
    }

    /// `node …/codex.js` launching the native `codex` binary is one session, not two: a
    /// node-hosted root whose only agent child has the same kind is dropped as a wrapper.
    /// Only a direct child counts: a delegated worker runs under a shell (a grandchild),
    /// and its npm-installed supervisor is a real session.
    static func launcherWrappers(_ roots: [ProcessRecord]) -> Set<Int32> {
        var wrappers: Set<Int32> = []
        for root in roots where root.name == "node" {
            let agentChildren = roots.filter { $0.ppid == root.pid }
            if agentChildren.count == 1, agentChildren[0].agentKind == root.agentKind { wrappers.insert(root.pid) }
        }
        return wrappers
    }

    /// "/" and the home directory itself say nothing about which project an agent is in.
    static func isWorkDirectory(_ directory: String, home: String) -> Bool {
        let trimmed = directory.count > 1 && directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return trimmed != "/" && trimmed != home
    }

    /// Checkouts worked in by writers from two or more independent lineages. Sessions are
    /// independent when they share no ancestor session: a supervisor and its workers, and
    /// workers of one supervisor, never collide with each other. Reviewers never collide.
    public static func collisions(
        _ sessions: [AgentSession],
        now: Date = Date(),
        minimumAge: TimeInterval = minimumCollisionAge,
        alwaysEligible: Int32? = nil
    ) -> [SessionCollision] {
        let byPID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.pid, $0) })
        func lineageRoot(_ session: AgentSession) -> Int32 {
            var current = session.pid
            var seen: Set<Int32> = [current]
            while let parent = byPID[current]?.parentSessionPID, byPID[parent] != nil, seen.insert(parent).inserted {
                current = parent
            }
            return current
        }
        let eligible = sessions.filter {
            $0.role.isWriter && ($0.pid == alwaysEligible || now.timeIntervalSince($0.startTime) >= minimumAge)
        }
        var byCheckout: [String: (GitContext, [AgentSession])] = [:]
        for session in eligible {
            for checkout in session.checkouts {
                byCheckout[checkout.checkoutRoot, default: (checkout, [])].1.append(session)
            }
        }
        return byCheckout.values.compactMap { checkout, members in
            guard Set(members.map(lineageRoot)).count > 1 else { return nil }
            return SessionCollision(checkout: checkout, sessionPIDs: members.map(\.pid).sorted())
        }
        .sorted { $0.checkout.checkoutRoot < $1.checkout.checkoutRoot }
    }
}
