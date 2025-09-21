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

                Section("Appearance") {
                    // Preview of the current avatar selection
                    HStack(spacing: 16) {
                        AvatarCircle(
                            handle: session.selectedHandle ?? "?",
                            url: session.selectedAvatarURL,
                            size: 48
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Profile image preview")
                                .font(.headline)
                            Text("Source: \(session.avatarSourcePreference.label)\(session.selectedHandle.map { "  •  @\($0)" } ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Choose which account provides the avatar, disabling options if not signed in
                    Picker("Profile image source", selection: Binding(get: { session.avatarSourcePreference }, set: { session.avatarSourcePreference = $0 })) {
                        Text(SessionStore.AvatarSource.auto.label).tag(SessionStore.AvatarSource.auto)
                        Text(SessionStore.AvatarSource.bluesky.label)
                            .tag(SessionStore.AvatarSource.bluesky)
                            .disabled(!session.isBlueskySignedIn)
                        Text(SessionStore.AvatarSource.mastodon.label)
                            .tag(SessionStore.AvatarSource.mastodon)
                            .disabled(!session.isMastodonSignedIn)
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Profile image source")

                    if !session.isBlueskySignedIn {
                        Text("Bluesky avatar unavailable: not signed in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !session.isMastodonSignedIn {
                        Text("Mastodon avatar unavailable: not signed in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
