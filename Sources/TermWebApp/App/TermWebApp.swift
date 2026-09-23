import SwiftUI

@main
struct TermWebApp: App {
    @State private var settings: SettingsStore
    @State private var model: ServerListModel
    @State private var launchAtLogin: LaunchAtLoginController
    private let actions: any ServerActions

    init() {
        let stores = AppStores(.live())
        _settings = State(initialValue: stores.settings)
        _model = State(initialValue: stores.model)
        _launchAtLogin = State(initialValue: stores.launchAtLogin)
        actions = stores.actions
        // The label must update while the panel is closed, so polling lives in the model.
        stores.model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
                .environment(settings)
                .environment(\.serverActions, actions)
        } label: {
            MenuBarLabel(count: model.visibleCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(launchAtLogin)
        }
    }
}
