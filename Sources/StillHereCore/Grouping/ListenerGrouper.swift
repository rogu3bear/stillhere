/// All listeners on one port, merged across address families and forked workers.
public struct ListenerGroup: Sendable, Hashable {
    public var port: Int
    public var rootPID: Int32
    public var rootCommand: String
    public var workerPIDs: [Int32]
    public var bindings: [Binding]

    public var memberPIDs: [Int32] { [rootPID] + workerPIDs }
}

/// Pure grouping of listener records by port and process tree.
public enum ListenerGrouper {
    /// Groups by port, merging IPv4/IPv6 sockets and processes linked by a parent/child
    /// relation on that port (forked workers). Unrelated processes that share a port
    /// (SO_REUSEPORT, or different bind addresses) become separate groups. The root is the
    /// member whose parent is not in the group (ties go to the lowest PID).
    public static func group(_ records: [ListenerRecord]) -> [ListenerGroup] {
        Dictionary(grouping: records, by: \.port)
            .flatMap { port, members in processTrees(members).map { makeGroup(port: port, members: $0) } }
            .sorted { ($0.port, $0.rootPID) < ($1.port, $1.rootPID) }
    }

    /// Splits one port's records into connected components of the parent/child graph.
    private static func processTrees(_ members: [ListenerRecord]) -> [[ListenerRecord]] {
        let pids = Set(members.map(\.pid))
        var representative = Dictionary(uniqueKeysWithValues: pids.map { ($0, $0) })
        func find(_ pid: Int32) -> Int32 {
            var current = pid
            while let next = representative[current], next != current { current = next }
            return current
        }
        for record in members {
            guard let ppid = record.ppid, pids.contains(ppid) else { continue }
            let (a, b) = (find(record.pid), find(ppid))
            if a != b { representative[max(a, b)] = min(a, b) }
        }
        return Dictionary(grouping: members) { find($0.pid) }.values.map { $0 }
    }

    private static func makeGroup(port: Int, members: [ListenerRecord]) -> ListenerGroup {
        var pids = Set<Int32>()
        var parentByPID: [Int32: Int32] = [:]
        var commandByPID: [Int32: String] = [:]
        for record in members {
            pids.insert(record.pid)
            if let ppid = record.ppid { parentByPID[record.pid] = ppid }
            if commandByPID[record.pid]?.isEmpty ?? true { commandByPID[record.pid] = record.command }
        }
        let roots = pids.filter { pid in
            guard let parent = parentByPID[pid] else { return true }
            return !pids.contains(parent)
        }
        let rootPID = (roots.isEmpty ? pids : roots).min()!
        return ListenerGroup(
            port: port,
            rootPID: rootPID,
            rootCommand: commandByPID[rootPID] ?? "",
            workerPIDs: pids.subtracting([rootPID]).sorted(),
            bindings: Array(Set(members.map(\.binding))).sorted()
        )
    }
}
