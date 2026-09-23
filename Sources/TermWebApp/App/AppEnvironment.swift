import Foundation
import ServiceManagement
import TermWebCore

/// The composition root: every dependency the app's stores and views need.
struct AppEnvironment {
    var detector: any ServerDetector
    var defaults: UserDefaults
    var signaller: ProcessSignaller
    var loginItems: any LoginItemService
    var actions: any ServerActions

    /// Real lsof + libproc detection, real signals, real login items.
    static func live() -> AppEnvironment {
        AppEnvironment(
            detector: DefaultServerDetector(),
            defaults: .standard,
            signaller: ProcessSignaller(system: DarwinSignalSystem()),
            loginItems: MainAppLoginItem(),
            actions: LiveServerActions()
        )
    }

    /// Canned servers; signals, login items and actions are inert.
    static func preview(scenario: FakeServerDetector.Scenario = .init()) -> AppEnvironment {
        AppEnvironment(
            detector: FakeServerDetector(scenario: scenario),
            defaults: UserDefaults(suiteName: "com.mlnavigator.term-web.preview") ?? .standard,
            signaller: ProcessSignaller(system: InertSignalSystem()),
            loginItems: InertLoginItem(),
            actions: InertServerActions()
        )
    }
}

/// The stores built from an environment. Created once per app (or preview).
struct AppStores {
    let settings: SettingsStore
    let model: ServerListModel
    let launchAtLogin: LaunchAtLoginController
    let actions: any ServerActions

    init(_ environment: AppEnvironment) {
        settings = SettingsStore(defaults: environment.defaults)
        model = ServerListModel(detector: environment.detector, settings: settings, signaller: environment.signaller)
        launchAtLogin = LaunchAtLoginController(service: environment.loginItems)
        actions = environment.actions
    }
}

/// Signals nothing: every PID is reported as gone.
nonisolated struct InertSignalSystem: SignalSystem {
    func send(_ signal: Int32, to pid: Int32) -> Int32 { ESRCH }
    func isAlive(_ pid: Int32) -> Bool { false }
    func startTime(of pid: Int32) -> StartTimeLookup { .notFound }
}

struct InertLoginItem: LoginItemService {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
