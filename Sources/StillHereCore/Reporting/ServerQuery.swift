import Foundation

/// One scan plus optional HTTP probes: what the CLI and the MCP server both answer from.
public struct ServerQuery: Sendable {
    public struct Filter: Sendable, Hashable {
        public var includeHidden = false
        /// Only servers started by this agent (session or agent process).
        public var owner: AgentOwner?
        public var orphansOnly = false
        public var port: Int?

        public init(includeHidden: Bool = false, owner: AgentOwner? = nil, orphansOnly: Bool = false, port: Int? = nil) {
            self.includeHidden = includeHidden
            self.owner = owner
            self.orphansOnly = orphansOnly
            self.port = port
        }

        public func matches(_ entry: ServerEntry) -> Bool {
            if !includeHidden, entry.isHidden { return false }
            if let port, entry.port != port { return false }
            if let owner, !owner.owns(entry.agent) { return false }
            if orphansOnly, entry.agent?.isOrphaned != true { return false }
            return true
        }
    }

    public static let maxConcurrentProbes = 4

    private let detector: any ServerDetector
    /// Read on every scan, so a long-running MCP server follows edits to the ignore list.
    private let rules: @Sendable () -> IgnoreConfiguration

    public init(detector: any ServerDetector = DefaultServerDetector(), config: IgnoreConfiguration = .defaults) {
        self.init(detector: detector, rules: { config })
    }

    public init(detector: any ServerDetector = DefaultServerDetector(), rules: @escaping @Sendable () -> IgnoreConfiguration) {
        self.detector = detector
        self.rules = rules
    }

    public func entries(_ filter: Filter = .init()) async throws -> [ServerEntry] {
        try await detector.scan(config: rules()).filter(filter.matches)
    }

    /// Filtered entries in port order, each with its probe when `probe` is true.
    public func run(_ filter: Filter = .init(), probe: Bool = true) async throws -> [(entry: ServerEntry, probe: ProbeResult?)] {
        let entries = try await entries(filter)
        guard probe else { return entries.map { ($0, nil) } }
        let probes = await probeAll(entries)
        return entries.map { ($0, probes[$0.id]) }
    }

    public func reports(_ filter: Filter = .init(), probe: Bool = true, now: Date = Date()) async throws -> [ServerReport] {
        try await run(filter, probe: probe).map { ServerReport(entry: $0.entry, probe: $0.probe, now: now) }
    }

    public func probe(_ entry: ServerEntry) async -> ProbeResult {
        await detector.probe(entry)
    }

    private func probeAll(_ entries: [ServerEntry]) async -> [ServerEntry.ID: ProbeResult] {
        await withTaskGroup(of: (ServerEntry.ID, ProbeResult).self) { group in
            var pending = entries.makeIterator()
            func enqueueNext() {
                guard let entry = pending.next() else { return }
                group.addTask { (entry.id, await detector.probe(entry)) }
            }
            for _ in 0..<Self.maxConcurrentProbes { enqueueNext() }
            var results: [ServerEntry.ID: ProbeResult] = [:]
            while let (id, result) = await group.next() {
                results[id] = result
                enqueueNext()
            }
            return results
        }
    }
}
