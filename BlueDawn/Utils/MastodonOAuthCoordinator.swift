import AuthenticationServices
import Foundation

@MainActor
final class MastodonOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct AppRegistration: Decodable {
        let client_id: String
        let client_secret: String
    }

    struct TokenResponse: Decodable {
        let access_token: String
    }

    enum OAuthError: LocalizedError {
        case invalidInstance
        case cancelled
        case missingCode
        case stateMismatch
        case registrationFailed
        case tokenExchangeFailed

        var errorDescription: String? {
            switch self {
            case .invalidInstance:
                return "Enter a valid Mastodon instance (for example, mastodon.social)."
            case .cancelled:
                return "Sign-in was canceled."
            case .missingCode:
                return "Missing authorization code from Mastodon."
            case .stateMismatch:
                return "Security check failed during authentication."
            case .registrationFailed:
                return "Failed to register the app with your instance."
            case .tokenExchangeFailed:
                return "Failed to exchange the authorization code for a token."
            }
        }
    }

    private var authSession: ASWebAuthenticationSession?

    func authenticate(instanceURL: URL) async throws -> String {
        let redirectURI = URL(string: "bluedawn://oauth/mastodon")!
        let app = try await registerApp(instanceURL: instanceURL, redirectURI: redirectURI)
        let codeVerifier = OAuthPKCE.makeCodeVerifier()
        let codeChallenge = OAuthPKCE.makeCodeChallenge(for: codeVerifier)
        let state = UUID().uuidString

        let authURL = try authorizationURL(
            instanceURL: instanceURL,
            clientID: app.client_id,
            redirectURI: redirectURI,
            scope: "read write follow",
            codeChallenge: codeChallenge,
            state: state
        )

        let callbackURL = try await startAuthSession(url: authURL, callbackScheme: redirectURI.scheme)
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            throw OAuthError.missingCode
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == state else { throw OAuthError.stateMismatch }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.missingCode
        }

        let token = try await exchangeToken(
            instanceURL: instanceURL,
            clientID: app.client_id,
            clientSecret: app.client_secret,
            redirectURI: redirectURI,
            code: code,
            codeVerifier: codeVerifier
        )

        return token
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
#if canImport(UIKit)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
#else
        return ASPresentationAnchor()
#endif
    }

    private func authorizationURL(
        instanceURL: URL,
        clientID: String,
        redirectURI: URL,
        scope: String,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(url: instanceURL.appending(path: "/oauth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else { throw OAuthError.invalidInstance }
        return url
    }

    private func registerApp(instanceURL: URL, redirectURI: URL) async throws -> AppRegistration {
        var url = instanceURL
        url.append(path: "/api/v1/apps")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_name": "BlueDawn",
            "redirect_uris": redirectURI.absoluteString,
            "scopes": "read write follow",
            "website": "https://github.com"
        ]
        request.httpBody = formURLEncoded(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.registrationFailed
        }

        return try JSONDecoder().decode(AppRegistration.self, from: data)
    }

    private func exchangeToken(
        instanceURL: URL,
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        code: String,
        codeVerifier: String
    ) async throws -> String {
        var url = instanceURL
        url.append(path: "/oauth/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI.absoluteString,
            "code": code,
            "code_verifier": codeVerifier,
            "scope": "read write follow"
        ]
        request.httpBody = formURLEncoded(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    private func startAuthSession(url: URL, callbackScheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                    return
                }
                if let url = callbackURL {
                    continuation.resume(returning: url)
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: OAuthError.missingCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    private func formURLEncoded(_ values: [String: String]) -> Data {
        let pairs = values.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}
