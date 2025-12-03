import SwiftUI

struct MastodonLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var instanceDomain: String = ""
    @State private var mastodonToken: String = ""

    var body: some View {
        Form {
            Section("Instance") {
                TextField("mastodon.social", text: $instanceDomain)
#if canImport(UIKit)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
#endif
            }
            Section("Authentication") {
                SecureField("Personal access token", text: $mastodonToken)
#if canImport(UIKit)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
#endif
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
