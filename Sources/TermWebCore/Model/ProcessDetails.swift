import Foundation

/// Details about one process, gathered off the main actor.
public struct ProcessDetails: Sendable, Hashable {
    public var pid: Int32
    public var ppid: Int32?
    public var uid: UInt32?
    /// Process name (libproc `pbi_name`/`pbi_comm`, or the ps command basename).
    public var name: String?
    public var startTime: Date?
    /// True when `startTime` was derived from `ps etime` (second resolution).
    public var startTimeIsApproximate: Bool
    public var executablePath: String?
    public var argv: [String]
    public var cwd: String?

    public init(
        pid: Int32,
        ppid: Int32? = nil,
        uid: UInt32? = nil,
        name: String? = nil,
        startTime: Date? = nil,
        startTimeIsApproximate: Bool = false,
        executablePath: String? = nil,
        argv: [String] = [],
        cwd: String? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.startTime = startTime
        self.startTimeIsApproximate = startTimeIsApproximate
        self.executablePath = executablePath
        self.argv = argv
        self.cwd = cwd
    }
}
