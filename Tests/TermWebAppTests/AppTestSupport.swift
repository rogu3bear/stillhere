import Darwin
import Foundation
import Synchronization
import TermWebCore
@testable import TermWebApp

/// Signal system for tests. A process "dies" on the signals listed in `fatalSignals`, and
/// dying also removes its port from the fake detector, like a real listener closing, or
/// hands the port to `successor` when one is set (another process grabbing the port).
nonisolated final class ScriptedSignalSystem: SignalSystem {
    struct State {
        var start: Date
        var name: String
        var uid: UInt32 = getuid()
        var alive = true
        var fatalSignals: Set<Int32>
        var successor: ServerEntry?
        var sent: [Int32] = []
    }

    private let state: Mutex<State>
    private let detector: FakeServerDetector
    private let port: Int

    init(start: Date, name: String, fatalSignals: Set<Int32>, detector: FakeServerDetector, port: Int) {
        state = Mutex(State(start: start, name: name, fatalSignals: fatalSignals))
        self.detector = detector
        self.port = port
    }

    var sent: [Int32] { state.withLock { $0.sent } }

    func update(_ body: (inout State) -> Void) { state.withLock { body(&$0) } }

    func send(_ signal: Int32, to pid: Int32) -> Int32 {
        let (died, successor) = state.withLock { state -> (Bool, ServerEntry?) in
            state.sent.append(signal)
            if state.fatalSignals.contains(signal) { state.alive = false }
            return (!state.alive, state.successor)
        }
        if died {
            var scenario = detector.scenario
            scenario.entries.removeAll { $0.port == port }
            if let successor { scenario.entries.append(successor) }
            detector.scenario = scenario
        }
        return 0
    }

    func isAlive(_ pid: Int32) -> Bool { state.withLock { $0.alive } }

    func lookup(_ pid: Int32) -> ProcessLookup {
        state.withLock { state in
            state.alive ? .found(LiveProcess(startTime: state.start, name: state.name, uid: state.uid)) : .notFound
        }
    }
}

/// A throwaway `UserDefaults` suite, removed when the test finishes with it.
final class TemporaryDefaults {
    let suiteName = "term-web.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        let plist = URL.libraryDirectory.appending(path: "Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}

extension ServerListModel {
    static func make(
        _ detector: FakeServerDetector,
        defaults: TemporaryDefaults = TemporaryDefaults(),
        signalSystem: any SignalSystem = InertSignalSystem()
    ) -> ServerListModel {
        ServerListModel(
            detector: detector,
            settings: SettingsStore(defaults: defaults.defaults),
            signaller: ProcessSignaller(system: signalSystem),
            clock: FixedNow(SampleServers.referenceDate),
            stopTimeout: .milliseconds(300),
            stopPollInterval: .milliseconds(10)
        )
    }
}
