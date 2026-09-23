import Foundation

/// Default inspector: exact start time, ppid, uid, cwd, executable path and argv
/// straight from the kernel, with no subprocess spawns.
public struct LibprocProcessInspector: ProcessInspector {
    public init() {}

    public func details(for pids: [Int32]) async -> [Int32: ProcessDetails] {
        var result: [Int32: ProcessDetails] = [:]
        for pid in Set(pids) {
            if let details = Self.details(for: pid) { result[pid] = details }
        }
        return result
    }

    static func details(for pid: Int32) -> ProcessDetails? {
        guard case .found(let info) = Libproc.bsdInfo(pid) else { return nil }
        let args = Libproc.procArgs(pid).flatMap(ProcArgsParser.parse)
        return ProcessDetails(
            pid: pid,
            ppid: info.ppid,
            uid: info.uid,
            name: info.name,
            startTime: info.startTime,
            executablePath: Libproc.executablePath(pid) ?? args?.executablePath,
            argv: args?.argv ?? [],
            cwd: Libproc.currentDirectory(pid),
            agentEnvironment: args?.agentEnvironment ?? [:]
        )
    }
}
