import SwiftUI

struct BlueskyLoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var identifier: String = ""  // email or handle
    @State private var appPassword: String = ""
    @State private var serviceBase: String = "https://bsky.social"
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        Form {
            Section("Service") {
                TextField("Service base", text: $serviceBase)
#if canImport(UIKit)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.URL)
                    .keyboardType(.URL)
#endif
            }
            Section("Account") {
                TextField("Identifier (email or handle)", text: $identifier)
#if canImport(UIKit)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.username)
#endif
                SecureField("App password", text: $appPassword)
#if canImport(UIKit)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.password)
#endif
                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        HStack {
                            ProgressView()
                            Text("Signing in…")
                        }
                    } else {
                        Text("Sign in to Bluesky")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(identifier.isEmpty || appPassword.isEmpty || isSigningIn)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Bluesky Login")
    }

    @MainActor private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        let trimmed = serviceBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = trimmed.isEmpty ? "https://bsky.social" : trimmed
        guard let serviceURL = URL(string: service),
              !identifier.isEmpty, !appPassword.isEmpty else {
            errorMessage = "Enter your handle/email and app password."
            return
        }

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
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Unable to sign in. Check your credentials and service URL."
                return
            }

            let sessionResp = try JSONDecoder().decode(CreateSessionResp.self, from: data)

            // Persist + activate
            session.setBlueskySession(pdsURL: serviceURL, accessToken: sessionResp.accessJwt, refreshJwt: sessionResp.refreshJwt, did: sessionResp.did, handle: sessionResp.handle)

            appPassword = "" // clear secret from memory/UI
        } catch {
            errorMessage = "Unable to sign in. Check your credentials and try again."
        }
    }
}
