import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var instanceDomain: String = ""
    @State private var mastodonToken: String = ""
    @State private var bskyIdentifier: String = ""   // email or handle (e.g., you.bsky.social)
    @State private var bskyAppPassword: String = ""  // app password from Bluesky settings
    @State private var bskyService: String = "https://bsky.social" // optional PDS/service base
    
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    SecureField("Personal access token (temporary)", text: $mastodonToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    Button {
                        Task { await signInMastodon() }
                    } label: {
                        Label("Sign in to Mastodon", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // Bluesky
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bluesky", systemImage: "cloud")
                        .font(.headline)
                    TextField("Identifier (email or handle)", text: $bskyIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)

                    SecureField("App password", text: $bskyAppPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)

                    TextField("Service base (optional)", text: $bskyService)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    Button {
                        Task { await signInBluesky() }
                    } label: {
                        Label("Sign in to Bluesky", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("BlueDawn")
        }
    }
    
    @MainActor private func signInMastodon() async {
        let trimmed = instanceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !mastodonToken.isEmpty,
              let url = URL(string: "https://\(trimmed)") else { return }
        session.mastodonClient = MastodonClient(baseURL: url, accessToken: mastodonToken)
        session.isMastodonSignedIn = true
        mastodonToken = ""
    }
    
    @MainActor
    private func signInBluesky() async {
        let service = bskyService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://bsky.social"
            : bskyService.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let serviceURL = URL(string: service),
            !bskyIdentifier.isEmpty,
            !bskyAppPassword.isEmpty
        else { return }

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
                return
            }

            let sessionResp = try JSONDecoder().decode(CreateSessionResp.self, from: data)
            session.blueskyClient = BlueskyClient(pdsURL: serviceURL, accessToken: sessionResp.accessJwt)
            session.isBlueskySignedIn = true
            session.signedInHandleBluesky = sessionResp.handle

            bskyAppPassword = ""
        } catch {
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
