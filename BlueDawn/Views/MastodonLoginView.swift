import SwiftUI

struct MastodonLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var instanceDomain: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var oauthCoordinator = MastodonOAuthCoordinator()

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
                Text("Sign in with Mastodon to authorize BlueDawn. Your token is stored securely in the keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        HStack {
                            ProgressView()
                            Text("Signing in…")
                        }
                    } else {
                        Text("Sign in to Mastodon")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSigningIn)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Mastodon Login")
    }

    @MainActor private func signIn() async {
        errorMessage = nil
        let trimmed = instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let instanceURL = normalizeInstanceURL(trimmed) else {
            errorMessage = MastodonOAuthCoordinator.OAuthError.invalidInstance.errorDescription
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let token = try await oauthCoordinator.authenticate(instanceURL: instanceURL)
            session.setMastodonSession(baseURL: instanceURL, accessToken: token)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to sign in to Mastodon."
        }
    }

    private func normalizeInstanceURL(_ input: String) -> URL? {
        guard !input.isEmpty else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: urlString), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
