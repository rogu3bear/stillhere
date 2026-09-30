import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab()
            }
            Tab("Ignore List", systemImage: "eye.slash") {
                IgnoreListTab()
            }
        }
        .frame(width: 480, height: 520)
    }
}
