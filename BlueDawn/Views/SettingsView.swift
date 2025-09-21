import SwiftUI

struct SettingsView: View {
    // Landing page for app settings
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    Toggle(isOn: Binding(get: { session.openLinksInApp }, set: { session.openLinksInApp = $0 })) {
                        Label("Open links in in-app browser", systemImage: "safari")
                    }

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
