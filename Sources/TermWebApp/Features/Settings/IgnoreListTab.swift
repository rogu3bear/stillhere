import SwiftUI

/// Structural hide rules plus the editable process-name and port lists.
struct IgnoreListTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var newName = ""
    @State private var newPort = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Hide automatically") {
                Toggle("System executables (/System, /usr/libexec, /usr/sbin)", isOn: $settings.hideSystemExecutables)
                Toggle("Daemons whose working folder is /", isOn: $settings.hideRootCwdDaemons)
                Toggle("Helpers inside other apps (.app bundles)", isOn: $settings.hideAppHelpers)
                Text("Interpreters such as node, python, ruby and bun are never hidden by these rules. Turning a rule off lists those processes; term-web still never stops them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.processNames, id: \.self) { name in
                    removableRow(name) { settings.removeProcessName(name) }
                }
                addRow(placeholder: "Process name (Name* matches a prefix)", text: $newName) {
                    settings.addProcessName(newName)
                }
            } header: {
                Text("Process names")
            } footer: {
                Text("Exact, case-insensitive match on the process name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ports") {
                ForEach(settings.ports, id: \.self) { port in
                    removableRow(String(port)) { settings.removePort(port) }
                }
                addRow(placeholder: "Port (1–65535)", text: $newPort) {
                    settings.addPort(newPort)
                }
            }

            Section {
                Button("Reset to Defaults") { settings.resetIgnoreList() }
            } footer: {
                Text("The term-web command and its MCP server for coding agents use this list too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func removableRow(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(text).monospaced()
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(text)")
        }
    }

    private func addRow(placeholder: String, text: Binding<String>, add: @escaping () -> Bool) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if add() { text.wrappedValue = "" } }
            Button("Add") { if add() { text.wrappedValue = "" } }
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
