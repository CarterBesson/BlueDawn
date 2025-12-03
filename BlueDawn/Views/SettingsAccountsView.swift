import SwiftUI

struct SettingsAccountsView: View {
    @Environment(SessionStore.self) private var session
    @State private var confirmMastoSignOut = false
    @State private var confirmBskySignOut = false

    var body: some View {
        List {
            Section("Accounts") {
                HStack {
                    Label("Mastodon", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    statusBadge(session.mastodonClient != nil)
                }
                NavigationLink("Mastodon Login…") { MastodonLoginView() }
                if session.mastodonClient != nil {
                    Button("Sign out of Mastodon", role: .destructive) { confirmMastoSignOut = true }
                }

                HStack {
                    Label("Bluesky", systemImage: "cloud")
                    Spacer()
                    statusBadge(session.blueskyClient != nil)
                }
                NavigationLink("Bluesky Login…") { BlueskyLoginView() }
                if session.blueskyClient != nil {
                    Button("Sign out of Bluesky", role: .destructive) { confirmBskySignOut = true }
                }
            }
        }
        .navigationTitle("Accounts")
        .alert("Sign out of Mastodon?", isPresented: $confirmMastoSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                session.mastodonClient = nil
                session.isMastodonSignedIn = false
                session.signedInHandleMastodon = nil
            }
        } message: {
            Text("This will remove your Mastodon token from this device.")
        }
        .alert("Sign out of Bluesky?", isPresented: $confirmBskySignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                session.blueskyClient = nil
                session.isBlueskySignedIn = false
                session.signedInHandleBluesky = nil
            }
        } message: {
            Text("This will remove your Bluesky token from this device.")
        }
    }

    @ViewBuilder
    private func statusBadge(_ connected: Bool) -> some View {
        if connected {
            Text("Connected").font(.caption).foregroundStyle(.green)
        } else {
            Text("Not connected").font(.caption).foregroundStyle(.secondary)
        }
    }
}

