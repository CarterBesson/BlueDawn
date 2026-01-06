import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var instanceDomain: String = ""
    @State private var mastodonError: String?
    @State private var isMastodonSigningIn = false
    @State private var oauthCoordinator = MastodonOAuthCoordinator()
    @State private var bskyIdentifier: String = ""   // email or handle (e.g., you.bsky.social)
    @State private var bskyAppPassword: String = ""  // app password from Bluesky settings
    @State private var bskyService: String = "https://bsky.social" // optional PDS/service base
    @State private var bskyError: String?
    @State private var isBlueskySigningIn = false

    private var fieldBackground: Color { Color.secondary.opacity(0.12) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Sign in to your networks")
                    .font(.title2.bold())

                // Mastodon
                VStack(alignment: .leading, spacing: 12) {
                    Label("Mastodon", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                    TextField("Your instance (e.g. mastodon.social)", text: $instanceDomain)
#if canImport(UIKit)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .keyboardType(.URL)
#endif
                        .padding(12)
                        .background(fieldBackground)
                        .cornerRadius(12)
                    Text("Use Mastodon to authorize BlueDawn. Your token is stored securely in the keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await signInMastodon() }
                    } label: {
                        if isMastodonSigningIn {
                            HStack {
                                ProgressView()
                                Text("Signing in…")
                            }
                        } else {
                            Label("Sign in to Mastodon", systemImage: "lock.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMastodonSigningIn)

                    if let mastodonError {
                        Text(mastodonError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                // Bluesky
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bluesky", systemImage: "cloud")
                        .font(.headline)
                    TextField("Identifier (email or handle)", text: $bskyIdentifier)
#if canImport(UIKit)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.username)
#endif
                        .padding(12)
                        .background(fieldBackground)
                        .cornerRadius(12)

                    SecureField("App password", text: $bskyAppPassword)
#if canImport(UIKit)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.password)
#endif
                        .padding(12)
                        .background(fieldBackground)
                        .cornerRadius(12)

                    TextField("Service base (optional)", text: $bskyService)
                        .padding(12)
#if canImport(UIKit)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .keyboardType(.URL)
#endif
                        .background(fieldBackground)
                        .cornerRadius(12)
                    Button {
                        Task { await signInBluesky() }
                    } label: {
                        if isBlueskySigningIn {
                            HStack {
                                ProgressView()
                                Text("Signing in…")
                            }
                        } else {
                            Label("Sign in to Bluesky", systemImage: "lock.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bskyIdentifier.isEmpty || bskyAppPassword.isEmpty || isBlueskySigningIn)

                    if let bskyError {
                        Text(bskyError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("BlueDawn")
        }
    }

    @MainActor private func signInMastodon() async {
        mastodonError = nil
        let trimmed = instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let instanceURL = normalizeInstanceURL(trimmed) else {
            mastodonError = MastodonOAuthCoordinator.OAuthError.invalidInstance.errorDescription
            return
        }

        isMastodonSigningIn = true
        defer { isMastodonSigningIn = false }

        do {
            let token = try await oauthCoordinator.authenticate(instanceURL: instanceURL)
            session.setMastodonSession(baseURL: instanceURL, accessToken: token)
        } catch {
            mastodonError = (error as? LocalizedError)?.errorDescription ?? "Unable to sign in to Mastodon."
        }
    }

    @MainActor
    private func signInBluesky() async {
        bskyError = nil
        isBlueskySigningIn = true
        defer { isBlueskySigningIn = false }

        let service = bskyService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://bsky.social"
            : bskyService.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let serviceURL = URL(string: service),
            !bskyIdentifier.isEmpty,
            !bskyAppPassword.isEmpty
        else {
            bskyError = "Enter your handle/email and app password."
            return
        }

        struct CreateSessionReq: Encodable {
            let identifier: String
            let password: String
        }
        struct CreateSessionResp: Decodable {
            let accessJwt: String
            let refreshJwt: String?
            let did: String
            let handle: String
        }

        do {
            var url = serviceURL
            url.append(path: "/xrpc/com.atproto.server.createSession")

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(CreateSessionReq(identifier: bskyIdentifier, password: bskyAppPassword))

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                bskyError = "Unable to sign in. Check your credentials."
                return
            }

            let sessionResp = try JSONDecoder().decode(CreateSessionResp.self, from: data)
            session.blueskyClient = BlueskyClient(pdsURL: serviceURL, accessToken: sessionResp.accessJwt, did: sessionResp.did)
            session.isBlueskySignedIn = true
            session.signedInHandleBluesky = sessionResp.handle
            session.blueskyDid = sessionResp.did

            bskyAppPassword = ""
        } catch {
            bskyError = "Unable to sign in. Check your credentials and try again."
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

#Preview {
    LoginView()
        .environment(SessionStore())
}
