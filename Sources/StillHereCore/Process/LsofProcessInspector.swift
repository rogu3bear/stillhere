import Foundation

/// Fallback inspector built on text tools: ONE batched `lsof -a -p PIDS -d cwd -Fn`
/// and ONE `ps -ww -o pid=,ppid=,etime=,command= -p PIDS`.
///
/// Limits (why libproc is the default): the start time is approximate (`etime` has
/// one-second resolution) and argv is the space-joined `command`, split on spaces.
public struct LsofProcessInspector: ProcessInspector {
    static let lsof = "/usr/sbin/lsof"
    static let ps = "/bin/ps"

    private let runner: any CommandRunner
    private let clock: any NowProvider
    private let timeout: Duration

    public init(runner: any CommandRunner = Subprocess(), clock: any NowProvider = SystemNow(), timeout: Duration = .seconds(5)) {
        self.runner = runner
        self.clock = clock
        self.timeout = timeout
    }

    public func details(for pids: [Int32]) async -> [Int32: ProcessDetails] {
        let unique = Array(Set(pids)).sorted()
        guard !unique.isEmpty else { return [:] }
        let list = unique.map(String.init).joined(separator: ",")

        // Both tools exit 1 when some PIDs vanished; partial output is still valid.
        async let cwdOutput = try? runner.run(Self.lsof, ["-a", "-p", list, "-d", "cwd", "-Fn"], timeout: timeout)
        async let psOutput = try? runner.run(Self.ps, ["-ww", "-o", "pid=,ppid=,etime=,command=", "-p", list], timeout: timeout)
        let cwds = await cwdOutput.map { LsofCwdParser.parse($0.text) } ?? [:]
        let rows = await psOutput.map { PsParser.parse($0.text) } ?? []

        let now = clock.now
        var result: [Int32: ProcessDetails] = [:]
        for row in rows where unique.contains(row.pid) {
            let argv = row.command.split(separator: " ").map(String.init)
            let executable = argv.first
            result[row.pid] = ProcessDetails(
                pid: row.pid,
                ppid: row.ppid,
                name: executable.map { ($0 as NSString).lastPathComponent },
                startTime: now.addingTimeInterval(-row.elapsed),
                startTimeIsApproximate: true,
                executablePath: executable.flatMap { $0.hasPrefix("/") ? $0 : nil },
                argv: argv,
                cwd: cwds[row.pid]
            )
        }
        return result
    }
}
