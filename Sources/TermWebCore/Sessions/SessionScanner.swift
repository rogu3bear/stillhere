import Foundation

/// Finds agent sessions in a process table and the checkouts they work in. Pure given its
/// inputs; `scan()` wires in libproc and `.git` reads.
public struct SessionScanner: Sendable {
    public init() {}

    /// Live scan of the current user's processes.
    public func scan(home: String = NSHomeDirectory()) -> [AgentSession] {
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
            home: home
        )
    }

    public static func isAgentRoot(_ record: ProcessRecord) -> Bool {
        record.agentKind != nil
    }

    public static func sessions(
        in table: ProcessTable,
        cwd: (Int32) -> String?,
        checkout: (String) -> GitContext?,
        home: String
    ) -> [AgentSession] {
        let roots = table.records.values.filter(isAgentRoot).sorted { $0.pid < $1.pid }
        let rootPIDs = Set(roots.map(\.pid))
        return roots.map { root in
            let parent = table.ancestors(of: root.pid).first { rootPIDs.contains($0.pid) }
            let members = [root] + table.descendants(of: root.pid, stopAt: isAgentRoot)
            var seen: Set<String> = []
            var checkouts: [GitContext] = []
            for member in members {
                guard let directory = cwd(member.pid), isWorkDirectory(directory, home: home),
                      let context = checkout(directory), seen.insert(context.checkoutRoot).inserted
                else { continue }
                checkouts.append(context)
            }
            return AgentSession(
                pid: root.pid,
                kind: root.agentKind ?? .other(root.name),
                startTime: root.startTime,
                cwd: cwd(root.pid),
                checkouts: checkouts.sorted { $0.checkoutRoot < $1.checkoutRoot },
                parentSessionPID: parent?.pid,
                memberPIDs: Set(members.map(\.pid))
            )
        }
    }

    /// "/" and the home directory itself say nothing about which project an agent is in.
    static func isWorkDirectory(_ directory: String, home: String) -> Bool {
        let trimmed = directory.count > 1 && directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return trimmed != "/" && trimmed != home
    }

    /// Checkouts with two or more sessions, none of which started another of them.
    public static func collisions(_ sessions: [AgentSession]) -> [SessionCollision] {
        let byPID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.pid, $0) })
        func lineage(_ session: AgentSession) -> Set<Int32> {
            var result: Set<Int32> = [session.pid]
            var next = session.parentSessionPID
            while let pid = next, result.insert(pid).inserted { next = byPID[pid]?.parentSessionPID }
            return result
        }
        var byCheckout: [String: (GitContext, [AgentSession])] = [:]
        for session in sessions {
            for checkout in session.checkouts {
                byCheckout[checkout.checkoutRoot, default: (checkout, [])].1.append(session)
            }
        }
        return byCheckout.values.compactMap { checkout, members in
            // Keep only sessions with no ancestor session in the same checkout.
            let independent = members.filter { member in
                !members.contains { other in other.pid != member.pid && lineage(member).contains(other.pid) }
            }
            guard independent.count > 1 else { return nil }
            return SessionCollision(checkout: checkout, sessionPIDs: independent.map(\.pid).sorted())
        }
        .sorted { $0.checkout.checkoutRoot < $1.checkout.checkoutRoot }
    }
}
