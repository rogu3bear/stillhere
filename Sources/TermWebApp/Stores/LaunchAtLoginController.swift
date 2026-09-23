import Foundation
import Observation
import ServiceManagement

/// The system login-item registration for this app. Injected so tests and previews never
/// touch Background Task Management.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct MainAppLoginItem: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Launch at login. The value is never stored: the system owns it and the user can change
/// it in System Settings, so the status is re-read on appear and on reactivation.
@Observable
final class LaunchAtLoginController {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService = MainAppLoginItem()) {
        self.service = service
        status = service.status
    }

    /// On for both an enabled item and one waiting for the user's approval.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = service.status
    }

    func set(on: Bool) {
        errorMessage = nil
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
