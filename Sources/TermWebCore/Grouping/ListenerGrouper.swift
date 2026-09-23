/// All listeners on one port, merged across address families and forked workers.
public struct ListenerGroup: Sendable, Hashable {
    public var port: Int
    public var rootPID: Int32
    public var rootCommand: String
    public var workerPIDs: [Int32]
    public var bindings: [Binding]

    public var memberPIDs: [Int32] { [rootPID] + workerPIDs }
}

/// Pure grouping of listener records by port.
public enum ListenerGrouper {
    /// Groups by port, merging IPv4/IPv6 sockets. The root is the member whose parent is
    /// not in the group (ties go to the lowest PID); the other members are workers.
    public static func group(_ records: [ListenerRecord]) -> [ListenerGroup] {
        Dictionary(grouping: records, by: \.port)
            .map { port, members in makeGroup(port: port, members: members) }
            .sorted { $0.port < $1.port }
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
