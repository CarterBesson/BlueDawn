import SwiftUI

struct MastodonLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var instanceDomain: String = ""
    @State private var mastodonToken: String = ""

    var body: some View {
        Form {
            Section("Instance") {
                TextField("mastodon.social", text: $instanceDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
            }
            Section("Authentication") {
                SecureField("Personal access token", text: $mastodonToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("Sign in to Mastodon", action: { Task { await signIn() } })
                    .buttonStyle(.borderedProminent)
                    .disabled(instanceDomain.isEmpty || mastodonToken.isEmpty)
            }
        }
        .navigationTitle("Mastodon Login")
    }

    @MainActor private func signIn() async {
        let trimmed = instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !mastodonToken.isEmpty, let url = URL(string: "https://\(trimmed)") else { return }
        // Save to keychain and session
        session.setMastodonSession(baseURL: url, accessToken: mastodonToken)
        mastodonToken = ""
    }
}
