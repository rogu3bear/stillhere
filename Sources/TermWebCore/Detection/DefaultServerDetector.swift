import Foundation

/// Live detector: listeners -> groups by port -> process details -> classification ->
/// manifest, git and agent provenance (visible rows only) -> framework guess. Runs on its
/// own actor, never on main.
public actor DefaultServerDetector: ServerDetector {
    private let listenerSource: any ListenerSource
    private let inspector: any ProcessInspector
    private let prober: any HTTPProber
    private let manifests: ManifestReader
    private let homeDirectory: String

    public init(
        listenerSource: any ListenerSource = LsofListenerSource(),
        inspector: any ProcessInspector = LibprocProcessInspector(),
        prober: any HTTPProber = URLSessionHTTPProber(),
        manifests: ManifestReader = ManifestReader(),
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.listenerSource = listenerSource
        self.inspector = inspector
        self.prober = prober
        self.manifests = manifests
        self.homeDirectory = homeDirectory
    }

    public func scan(config: IgnoreConfiguration) async throws -> [ServerEntry] {
        let groups = ListenerGrouper.group(try await listenerSource.listeners())
        let details = await inspector.details(for: groups.flatMap(\.memberPIDs))
        var entries: [ServerEntry] = []
        entries.reserveCapacity(groups.count)
        for group in groups {
            entries.append(await makeEntry(group, process: details[group.rootPID], config: config))
        }
        return entries
    }

    public func probe(_ entry: ServerEntry) async -> ProbeResult {
        await prober.probe(port: entry.port, bindings: entry.bindings)
    }

    private func makeEntry(_ group: ListenerGroup, process: ProcessDetails?, config: IgnoreConfiguration) async -> ServerEntry {
        let hiddenReason = IgnoreClassifier.classify(group, details: process, config: config)
        let cwd = process?.cwd
        var manifest: ManifestFacts?
        if hiddenReason == nil, let cwd,
           let directory = ManifestLocator.locate(from: cwd, home: homeDirectory) {
            manifest = await manifests.facts(in: directory)
        }
        let project = cwd.flatMap { cwd -> ProjectLocation? in
            guard cwd != "/" else { return nil }
            let cwdURL = URL(fileURLWithPath: cwd, isDirectory: true)
            return ProjectLocation(cwd: cwdURL, projectRoot: manifest?.directory ?? cwdURL)
        }
        let framework = FrameworkDetector.guess(FrameworkSignals(
            argv: process?.argv ?? [],
            name: process?.name ?? group.rootCommand,
            executablePath: process?.executablePath,
            cwd: cwd,
            manifest: manifest
        ))
        var git: GitContext?
        var agent: AgentContext?
        if hiddenReason == nil, let process {
            if let project, cwd != nil {
                git = GitReader.context(for: project.projectRoot.path(percentEncoded: false), home: homeDirectory)
            }
            agent = await agentContext(for: process)
        }
        return ServerEntry(
            port: group.port,
            rootPID: group.rootPID,
            workerPIDs: group.workerPIDs,
            bindings: group.bindings,
            command: group.rootCommand,
            process: process,
            project: project,
            framework: framework,
            hiddenReason: hiddenReason,
            git: git,
            agent: agent
        )
    }

    /// Ancestors are gathered only while no environment marker already names the agent
    /// with a launcher PID; the launcher itself is looked up to tell alive from orphaned.
    private func agentContext(for process: ProcessDetails) async -> AgentContext? {
        let environment = process.agentEnvironment
        // The same condition AgentDetector uses to trust a launcher PID.
        let launcherPID = AgentDetector.fromEnvironment(environment)?.launcherPID
        var known: [Int32: ProcessDetails] = [:]
        if let launcherPID {
            known = await inspector.details(for: [launcherPID])
        }
        var ancestors: [ProcessDetails] = []
        if launcherPID == nil {
            var next = process.ppid
            while let pid = next, pid > 1, ancestors.count < Self.maxAncestors {
                guard let parent = await inspector.details(for: [pid])[pid] else { break }
                ancestors.append(parent)
                next = parent.ppid
            }
        }
        return AgentDetector.detect(
            environment: environment,
            ancestors: ancestors,
            serverStart: process.startTime,
            lookup: { known[$0] }
        )
    }

    static let maxAncestors = 12
}
