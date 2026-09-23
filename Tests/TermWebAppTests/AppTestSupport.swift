import Darwin
import Foundation
import Synchronization
import TermWebCore
@testable import TermWebApp

/// Signal system for tests. A process "dies" on the signals listed in `fatalSignals`, and
/// dying also removes its port from the fake detector, like a real listener closing.
nonisolated final class ScriptedSignalSystem: SignalSystem {
    struct State {
        var start: StartTimeLookup
        var alive = true
        var fatalSignals: Set<Int32>
        var sent: [Int32] = []
    }

    private let state: Mutex<State>
    private let detector: FakeServerDetector
    private let port: Int

    init(start: Date, fatalSignals: Set<Int32>, detector: FakeServerDetector, port: Int) {
        state = Mutex(State(start: .found(start), fatalSignals: fatalSignals))
        self.detector = detector
        self.port = port
    }

    var sent: [Int32] { state.withLock { $0.sent } }

    func send(_ signal: Int32, to pid: Int32) -> Int32 {
        let died = state.withLock { state -> Bool in
            state.sent.append(signal)
            if state.fatalSignals.contains(signal) { state.alive = false }
            return !state.alive
        }
        if died {
            var scenario = detector.scenario
            scenario.entries.removeAll { $0.port == port }
            detector.scenario = scenario
        }
        return 0
    }

    func isAlive(_ pid: Int32) -> Bool { state.withLock { $0.alive } }
    func startTime(of pid: Int32) -> StartTimeLookup { state.withLock { $0.start } }
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
