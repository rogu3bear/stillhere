import Foundation

/// Waits for a port to start listening and, optionally, to answer HTTP: the question an
/// agent asks right after starting a dev server.
public struct ServerWaiter: Sendable {
    public struct Outcome: Sendable {
        public var entry: ServerEntry?
        public var probe: ProbeResult?
        public var waited: Duration

        /// Listening, and answering HTTP when that was required.
        public var ready: Bool
    }

    private let query: ServerQuery
    private let pollInterval: Duration

    public init(query: ServerQuery = ServerQuery(), pollInterval: Duration = .milliseconds(250)) {
        self.query = query
        self.pollInterval = pollInterval
    }

    /// Hidden rows count too: the caller named the port explicitly. The deadline is
    /// checked before each probe, so a result can arrive at most one probe (about 2 s, or
    /// 4 s with the HTTPS fallback) after `timeout`.
    public func wait(port: Int, timeout: Duration, requireHTTP: Bool) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        var last: (ServerEntry, ProbeResult?)?
        while true {
            if let entry = try? await query.entries(.init(includeHidden: true, port: port)).first {
                let probe: ProbeResult?
                if !requireHTTP {
                    probe = nil
                } else if clock.now - start >= timeout, let previous = last {
                    probe = previous.1 // past the deadline: don't start another probe
                } else {
                    probe = await query.probe(entry) // includes the one check a zero timeout gets
                }
                last = (entry, probe)
                // Any HTTP status means the server is up; 5xx is the app's problem, not ours.
                if !requireHTTP || probe?.status != nil {
                    return Outcome(entry: entry, probe: probe, waited: clock.now - start, ready: true)
                }
            }
            if clock.now - start >= timeout || Task.isCancelled {
                return Outcome(entry: last?.0, probe: last?.1, waited: clock.now - start, ready: false)
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}
