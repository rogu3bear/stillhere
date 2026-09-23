import Darwin

/// Live `kill(2)` + libproc implementation.
public struct DarwinSignalSystem: SignalSystem {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> Int32 {
        kill(pid, signal) == 0 ? 0 : errno
    }

    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public func startTime(of pid: Int32) -> StartTimeLookup {
        switch Libproc.bsdInfo(pid) {
        case .found(let info): .found(info.startTime)
        case .notFound: .notFound
        case .denied: .denied
        }
    }
}
