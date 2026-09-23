import Foundation

/// One process in a table snapshot.
public struct ProcessRecord: Sendable, Hashable {
    public var pid: Int32
    public var ppid: Int32
    public var name: String
    public var startTime: Date
    /// Set only when it identifies an agent (see `ProcessTable.snapshot`).
    public var agentKind: AgentContext.Kind?

    public init(pid: Int32, ppid: Int32, name: String, startTime: Date, agentKind: AgentContext.Kind? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.startTime = startTime
        self.agentKind = agentKind ?? AgentMarkers.kind(name: name, executablePath: nil)
    }
}

/// A snapshot of the current user's processes with parent/child links.
public struct ProcessTable: Sendable {
    public let records: [Int32: ProcessRecord]
    private let children: [Int32: [Int32]]

    public init(_ records: [ProcessRecord]) {
        self.records = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [Int32: [Int32]] = [:]
        for record in records where record.ppid != record.pid {
            children[record.ppid, default: []].append(record.pid)
        }
        self.children = children.mapValues { $0.sorted() }
    }

    public func children(of pid: Int32) -> [Int32] { children[pid] ?? [] }

    /// Parent chain, nearest first, bounded against malformed (cyclic) tables.
    public func ancestors(of pid: Int32, limit: Int = 64) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var seen: Set<Int32> = [pid]
        var next = records[pid]?.ppid
        while let current = next, current > 1, result.count < limit, seen.insert(current).inserted,
              let record = records[current] {
            result.append(record)
            next = record.ppid
        }
        return result
    }

    /// Descendants breadth-first, not descending below PIDs `stopAt` accepts.
    public func descendants(of pid: Int32, stopAt: (ProcessRecord) -> Bool = { _ in false }) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var queue = children(of: pid)
        var seen: Set<Int32> = [pid]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard seen.insert(current).inserted, let record = records[current] else { continue }
            if stopAt(record) { continue }
            result.append(record)
            queue.append(contentsOf: children(of: current))
        }
        return result
    }

    /// The current user's processes, straight from libproc (a few ms for ~1000 PIDs).
    /// The executable path is read for every process; argv only for `node`, the one host
    /// whose agents can't be told apart by path.
    public static func snapshot(uid: UInt32 = getuid()) -> ProcessTable {
        var records: [ProcessRecord] = []
        for pid in Libproc.allPIDs() {
            guard case .found(let info) = Libproc.bsdInfo(pid), info.uid == uid else { continue }
            let path = Libproc.executablePath(pid)
            let argv = info.name == "node" ? Libproc.procArgs(pid).flatMap(ProcArgsParser.parse)?.argv ?? [] : []
            let kind = AgentMarkers.kind(name: info.name, executablePath: path, argv: argv)
            records.append(ProcessRecord(pid: pid, ppid: info.ppid, name: info.name, startTime: info.startTime, agentKind: kind))
        }
        return ProcessTable(records)
    }
}
