import SwiftUI

struct BlueskyLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var identifier: String = ""  // email or handle
    @State private var appPassword: String = ""
    @State private var serviceBase: String = "https://bsky.social"

    var body: some View {
        Form {
            Section("Service") {
                TextField("Service base", text: $serviceBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
            }
            Section("Account") {
                TextField("Identifier (email or handle)", text: $identifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                SecureField("App password", text: $appPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("Sign in to Bluesky") {
                    Task { await signIn() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(identifier.isEmpty || appPassword.isEmpty)
            }
        }
        .navigationTitle("Bluesky Login")
    }

    @MainActor private func signIn() async {
        let trimmed = serviceBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = trimmed.isEmpty ? "https://bsky.social" : trimmed
        guard let serviceURL = URL(string: service),
              !identifier.isEmpty, !appPassword.isEmpty else { return }

        struct CreateSessionReq: Encodable { let identifier: String; let password: String }
        struct CreateSessionResp: Decodable { let accessJwt: String; let refreshJwt: String; let did: String; let handle: String }

        do {
            var url = serviceURL
            url.append(path: "/xrpc/com.atproto.server.createSession")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = try JSONEncoder().encode(CreateSessionReq(identifier: identifier, password: appPassword))

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }

            let sessionResp = try JSONDecoder().decode(CreateSessionResp.self, from: data)

            // Persist + activate
            session.setBlueskySession(pdsURL: serviceURL, accessToken: sessionResp.accessJwt, refreshJwt: sessionResp.refreshJwt, handle: sessionResp.handle)

            appPassword = "" // clear secret from memory/UI
        } catch {
            // TODO: surface an error to the user
        }
    }
}
