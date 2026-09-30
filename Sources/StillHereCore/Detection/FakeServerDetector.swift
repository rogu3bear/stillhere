import Synchronization

/// Canned detector for tests and SwiftUI previews. The scenario can be changed at any
/// time; every call is recorded.
public final class FakeServerDetector: ServerDetector {
    public struct Scenario: Sendable {
        public var entries: [ServerEntry]
        public var probes: [Int: ProbeResult]
        public var scanError: DetectionError?
        public var delay: Duration

        public init(
            entries: [ServerEntry] = SampleServers.all,
            probes: [Int: ProbeResult] = SampleServers.probes,
            scanError: DetectionError? = nil,
            delay: Duration = .zero
        ) {
            self.entries = entries
            self.probes = probes
            self.scanError = scanError
            self.delay = delay
        }
    }

    private struct State {
        var scenario: Scenario
        var scanCount = 0
        var probedPorts: [Int] = []
        var lastConfig: IgnoreConfiguration?
    }

    private let state: Mutex<State>

    public init(scenario: Scenario = Scenario()) {
        state = Mutex(State(scenario: scenario))
    }

    public var scenario: Scenario {
        get { state.withLock { $0.scenario } }
        set { state.withLock { $0.scenario = newValue } }
    }

    public var scanCount: Int { state.withLock { $0.scanCount } }
    public var probedPorts: [Int] { state.withLock { $0.probedPorts } }
    public var lastConfig: IgnoreConfiguration? { state.withLock { $0.lastConfig } }

    public func scan(config: IgnoreConfiguration) async throws -> [ServerEntry] {
        let scenario = state.withLock { state in
            state.scanCount += 1
            state.lastConfig = config
            return state.scenario
        }
        if scenario.delay > .zero { try await Task.sleep(for: scenario.delay) }
        if let error = scenario.scanError { throw error }
        return scenario.entries
    }

    public func probe(_ entry: ServerEntry) async -> ProbeResult {
        let scenario = state.withLock { state in
            state.probedPorts.append(entry.port)
            return state.scenario
        }
        if scenario.delay > .zero { try? await Task.sleep(for: scenario.delay) }
        return scenario.probes[entry.port] ?? ProbeResult(host: ProbeHosts.ipv4, failure: .refused)
    }
}
