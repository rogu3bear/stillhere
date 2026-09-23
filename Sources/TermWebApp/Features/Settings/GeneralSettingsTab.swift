import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LaunchAtLoginController.self) private var launchAtLogin
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(SettingsStore.refreshIntervals, id: \.self) { seconds in
                        Text("\(Int(seconds)) seconds").tag(seconds)
                    }
                }
                Toggle("Show hidden servers", isOn: $settings.showHiddenServers)
                Toggle("Check HTTP status and page title", isOn: $settings.probeHTTP)
            } footer: {
                Text("Status checks send one GET to 127.0.0.1 or [::1] while the menu is open. Nothing leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Open folders in", selection: $settings.terminalBundleID) {
                    Text("Automatic (\(TerminalApp.resolve(preferred: nil).name))").tag(String?.none)
                    ForEach(TerminalApp.installed) { terminal in
                        Text(terminal.name).tag(Optional(terminal.bundleID))
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isOn },
                    set: { launchAtLogin.set(on: $0) }
                ))
                if launchAtLogin.requiresApproval {
                    HStack {
                        Text("Allow term-web in Login Items to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .onChange(of: appearsActive) { _, active in
            if active { launchAtLogin.refresh() }
        }
    }
}
