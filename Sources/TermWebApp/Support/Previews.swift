import SwiftUI
import TermWebCore

/// Preview wiring: `FakeServerDetector` + `SampleServers`, inert signals and actions.
@MainActor
private enum PreviewSupport {
    static func stores(_ scenario: FakeServerDetector.Scenario = .init()) -> AppStores {
        let stores = AppStores(.preview(scenario: scenario))
        stores.model.isPanelOpen = true
        return stores
    }
}

private struct PreviewHost<Content: View>: View {
    let stores: AppStores
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(stores.model)
            .environment(stores.settings)
            .environment(stores.launchAtLogin)
            .environment(\.serverActions, stores.actions)
            .task { await stores.model.refresh(.menuOpened) }
    }
}

#Preview("Menu") {
    PreviewHost(stores: PreviewSupport.stores()) { MenuPanel() }
}

#Preview("Menu, empty") {
    PreviewHost(stores: PreviewSupport.stores(.init(entries: []))) { MenuPanel() }
}

#Preview("Row") {
    PreviewHost(stores: PreviewSupport.stores()) {
        ServerRow(entry: SampleServers.vite).frame(width: 400)
    }
}

#Preview("Settings") {
    PreviewHost(stores: PreviewSupport.stores()) { SettingsView() }
}
