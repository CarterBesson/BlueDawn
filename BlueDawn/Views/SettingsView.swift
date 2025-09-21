import SwiftUI

struct SettingsView: View {
    // Landing page for app settings

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink {
                        SettingsAccountsView()
                    } label: {
                        Label("Accounts", systemImage: "person.2")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
