import Foundation
import ServiceManagement
import Testing
import TermWebCore
@testable import TermWebApp

@Suite struct SettingsStoreTests {
    let temp = TemporaryDefaults()

    @Test func defaults() {
        let settings = SettingsStore(defaults: temp.defaults)
        #expect(settings.refreshInterval == 5)
        #expect(!settings.showHiddenServers)
        #expect(settings.probeHTTP)
        #expect(settings.ignoreConfiguration == .defaults)
        #expect(temp.defaults.integer(forKey: SettingsStore.Key.schemaVersion) == 1)
    }

    @Test func roundTrip() {
        let settings = SettingsStore(defaults: temp.defaults)
        settings.refreshInterval = 10
        settings.showHiddenServers = true
        settings.probeHTTP = false
        settings.hideAppHelpers = false
        #expect(settings.addProcessName("  Python "))
        #expect(!settings.addProcessName("python")) // case-insensitive duplicate
        #expect(!settings.addProcessName("   "))
        #expect(settings.addPort("9000"))
        #expect(!settings.addPort("9000"))
        #expect(!settings.addPort("70000"))
        #expect(!settings.addPort("abc"))
        settings.removeProcessName("postgres")
        settings.removePort(5432)

        let reloaded = SettingsStore(defaults: temp.defaults)
        #expect(reloaded.refreshInterval == 10)
        #expect(reloaded.showHiddenServers)
        #expect(!reloaded.probeHTTP)
        #expect(!reloaded.hideAppHelpers)
        #expect(reloaded.processNames.last == "Python")
        #expect(!reloaded.processNames.contains("postgres"))
        #expect(reloaded.ports.contains(9000))
        #expect(!reloaded.ports.contains(5432))
        #expect(reloaded.ignoreConfiguration == settings.ignoreConfiguration)
    }

    @Test func invalidStoredIntervalFallsBackToDefault() {
        temp.defaults.set(7.0, forKey: SettingsStore.Key.refreshInterval)
        #expect(SettingsStore(defaults: temp.defaults).refreshInterval == 5)
    }

    @Test func resetRestoresOnlyTheIgnoreRules() {
        let settings = SettingsStore(defaults: temp.defaults)
        settings.refreshInterval = 30
        settings.hideSystemExecutables = false
        settings.addProcessName("node")
        settings.removePort(3306)
        settings.resetIgnoreList()

        #expect(settings.ignoreConfiguration == .defaults)
        #expect(settings.refreshInterval == 30)
        #expect(SettingsStore(defaults: temp.defaults).ignoreConfiguration == .defaults)
    }

    @Test func launchAtLoginIsReadFromTheSystemNotStored() {
        let service = RecordingLoginItem()
        let controller = LaunchAtLoginController(service: service)
        #expect(!controller.isOn)

        controller.set(on: true)
        #expect(controller.isOn)
        #expect(service.calls == ["register"])

        service.status = .requiresApproval
        controller.refresh()
        #expect(controller.isOn && controller.requiresApproval)

        service.failure = CocoaError(.featureUnsupported)
        controller.set(on: false)
        #expect(controller.errorMessage != nil)
        #expect(controller.isOn)
    }
}

final class RecordingLoginItem: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var failure: (any Error)?
    private(set) var calls: [String] = []

    func register() throws {
        calls.append("register")
        if let failure { throw failure }
        status = .enabled
    }

    func unregister() throws {
        calls.append("unregister")
        if let failure { throw failure }
        status = .notRegistered
    }

    func openSystemSettings() { calls.append("openSystemSettings") }
}
