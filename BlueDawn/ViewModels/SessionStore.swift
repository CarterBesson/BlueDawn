import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    // observed session state
    var blueskyClient: BlueskyClient?
    var mastodonClient: MastodonClient?
    var isBlueskySignedIn = false
    var isMastodonSignedIn = false
    var signedInHandleBluesky: String?
    var signedInHandleMastodon: String?
    var blueskyDid: String?
    // Shared per-post interaction cache
    var postStates: [String: PostInteractionState] = [:]

    // MARK: - Persistence keys
    private let KC_SERVICE = "BlueDawn"

    private let KC_BSKY_TOKEN = "bluesky.token"
    private let KC_BSKY_REFRESH = "bluesky.refresh"
    private let UD_BSKY_PDS   = "bd.bluesky.pds"
    private let UD_BSKY_HANDLE = "bd.bluesky.handle"

    private let KC_MASTO_TOKEN = "mastodon.token"
    private let UD_MASTO_BASE  = "bd.mastodon.base"

    // MARK: - Restore on launch
    func restoreOnLaunch() async {
        // Bluesky
        if let token = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_TOKEN),
           let pdsString = UserDefaults.standard.string(forKey: UD_BSKY_PDS),
           let pdsURL = URL(string: pdsString) {
            blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: token, did: nil)
            isBlueskySignedIn = true
            signedInHandleBluesky = UserDefaults.standard.string(forKey: UD_BSKY_HANDLE)
            // Attempt to refresh token and populate DID/handle
            _ = await refreshBlueskyIfNeeded()
            await populateBlueskyIdentityIfNeeded()
        }

        // Mastodon
        if let token = Keychain.loadToken(service: KC_SERVICE, account: KC_MASTO_TOKEN),
           let baseString = UserDefaults.standard.string(forKey: UD_MASTO_BASE),
           let baseURL = URL(string: baseString) {
            mastodonClient = MastodonClient(baseURL: baseURL, accessToken: token)
            isMastodonSignedIn = true
        }
    }

    // MARK: - Set sessions
    func setBlueskySession(pdsURL: URL, accessToken: String, refreshJwt: String, did: String, handle: String) {
        Keychain.save(token: accessToken, service: KC_SERVICE, account: KC_BSKY_TOKEN)
        Keychain.save(token: refreshJwt, service: KC_SERVICE, account: KC_BSKY_REFRESH)
        UserDefaults.standard.set(pdsURL.absoluteString, forKey: UD_BSKY_PDS)
        UserDefaults.standard.set(handle, forKey: UD_BSKY_HANDLE)

        blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: accessToken, did: did)
        isBlueskySignedIn = true
        signedInHandleBluesky = handle
        blueskyDid = did
    }

    func setMastodonSession(baseURL: URL, accessToken: String) {
        Keychain.save(token: accessToken, service: KC_SERVICE, account: KC_MASTO_TOKEN)
        UserDefaults.standard.set(baseURL.absoluteString, forKey: UD_MASTO_BASE)

        mastodonClient = MastodonClient(baseURL: baseURL, accessToken: accessToken)
        isMastodonSignedIn = true
    }

    /// Attempts to refresh the Bluesky session using the saved refresh JWT.
    /// Returns true if a new access token was obtained and the client was updated.
    func refreshBlueskyIfNeeded() async -> Bool {
        guard
            let pdsString = UserDefaults.standard.string(forKey: UD_BSKY_PDS),
            let pdsURL = URL(string: pdsString),
            let refresh = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_REFRESH)
        else { return false }

        var url = pdsURL
        url.append(path: "/xrpc/com.atproto.server.refreshSession")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        struct RefreshResp: Decodable { let accessJwt: String; let refreshJwt: String; let handle: String? }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let decoded = try JSONDecoder().decode(RefreshResp.self, from: data)

            // Persist new tokens
            Keychain.save(token: decoded.accessJwt, service: KC_SERVICE, account: KC_BSKY_TOKEN)
            Keychain.save(token: decoded.refreshJwt, service: KC_SERVICE, account: KC_BSKY_REFRESH)
            if let h = decoded.handle { UserDefaults.standard.set(h, forKey: UD_BSKY_HANDLE) }

            // Hydrate client
            blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: decoded.accessJwt, did: blueskyDid)
            isBlueskySignedIn = true
            if let h = decoded.handle { signedInHandleBluesky = h }
            // Ensure DID is populated post-refresh
            await populateBlueskyIdentityIfNeeded()
            return true
        } catch {
            return false
        }
    }

    private func populateBlueskyIdentityIfNeeded() async {
        guard let client = blueskyClient, client.did == nil else { return }
        var url = client.pdsURL; url.append(path: "/xrpc/com.atproto.server.getSession")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(client.accessToken)", forHTTPHeaderField: "Authorization")
        struct SessionResp: Decodable { let did: String; let handle: String }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let decoded = try JSONDecoder().decode(SessionResp.self, from: data)
            blueskyDid = decoded.did
            var updated = client
            updated.did = decoded.did
            blueskyClient = updated
            signedInHandleBluesky = decoded.handle
        } catch { /* ignore */ }
    }

    // MARK: - Sign out
    func signOutBluesky() {
        blueskyClient = nil
        isBlueskySignedIn = false
        signedInHandleBluesky = nil
        Keychain.delete(service: KC_SERVICE, account: KC_BSKY_TOKEN)
        Keychain.delete(service: KC_SERVICE, account: KC_BSKY_REFRESH)
        UserDefaults.standard.removeObject(forKey: UD_BSKY_PDS)
        UserDefaults.standard.removeObject(forKey: UD_BSKY_HANDLE)
    }

    func signOutMastodon() {
        mastodonClient = nil
        isMastodonSignedIn = false
        signedInHandleMastodon = nil
        Keychain.delete(service: KC_SERVICE, account: KC_MASTO_TOKEN)
        UserDefaults.standard.removeObject(forKey: UD_MASTO_BASE)
    }

    // MARK: - Shared post state helpers
    func state(for post: UnifiedPost) -> PostInteractionState {
        if let s = postStates[post.id] { return s }
        let s = PostInteractionState.fromPost(post)
        postStates[post.id] = s
        return s
    }

    func updateState(for postID: String, _ mutate: (inout PostInteractionState) -> Void) {
        var s = postStates[postID] ?? PostInteractionState(isLiked: false, isReposted: false, isBookmarked: false, likeCount: 0, repostCount: 0, bskyLikeRkey: nil, bskyRepostRkey: nil)
        mutate(&s)
        postStates[postID] = s
    }
}
