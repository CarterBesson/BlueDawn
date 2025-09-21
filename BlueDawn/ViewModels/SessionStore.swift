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
    // Current user avatars (populated on sign-in/restore)
    var avatarURLBluesky: URL? = nil
    var avatarURLMastodon: URL? = nil

    enum AvatarSource: String, CaseIterable, Identifiable {
        case auto
        case bluesky
        case mastodon
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto"
            case .bluesky: return "Bluesky"
            case .mastodon: return "Mastodon"
            }
        }
    }

    // MARK: - Persistence keys
    private let KC_SERVICE = "BlueDawn"

    private let KC_BSKY_TOKEN = "bluesky.token"
    private let KC_BSKY_REFRESH = "bluesky.refresh"
    private let UD_BSKY_PDS   = "bd.bluesky.pds"
    private let UD_BSKY_HANDLE = "bd.bluesky.handle"

    private let KC_MASTO_TOKEN = "mastodon.token"
    private let UD_MASTO_BASE  = "bd.mastodon.base"
    private let UD_OPEN_LINKS_IN_APP = "bd.links.inApp"
    private let UD_PROFILE_AVATAR_SOURCE = "bd.avatar.source"
    private let UD_VIDEO_START_MUTED = "bd.video.startMuted"
    private let UD_VIDEO_AUTOPLAY = "bd.video.autoplay"
    private let UD_VIDEO_LOOP = "bd.video.loop"

    // MARK: - JWT helpers
    private func jwtExpirationDate(_ jwt: String) -> Date? {
        // JWT format: header.payload.signature (all base64url)
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadB64 = String(parts[1])
        // Convert base64url to base64
        var base64 = payloadB64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // pad to multiple of 4
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let exp = json["exp"] as? Double { return Date(timeIntervalSince1970: exp) }
        if let expInt = json["exp"] as? Int { return Date(timeIntervalSince1970: TimeInterval(expInt)) }
        return nil
    }

    // MARK: - App settings
    // Default to true unless explicitly set
    var openLinksInApp: Bool = {
        let key = "bd.links.inApp"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(openLinksInApp, forKey: UD_OPEN_LINKS_IN_APP) }
    }

    // Whether videos should start muted by default
    var videoStartMuted: Bool = {
        let key = "bd.video.startMuted"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(videoStartMuted, forKey: UD_VIDEO_START_MUTED) }
    }

    // Autoplay videos when the view appears
    var videoAutoplay: Bool = {
        let key = "bd.video.autoplay"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(videoAutoplay, forKey: UD_VIDEO_AUTOPLAY) }
    }

    // Loop videos and GIFs when they reach the end
    var videoLoop: Bool = {
        let key = "bd.video.loop"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(videoLoop, forKey: UD_VIDEO_LOOP) }
    }

    // Which account's avatar to show in UI
    var avatarSourcePreference: AvatarSource = {
        if let raw = UserDefaults.standard.string(forKey: "bd.avatar.source"), let v = AvatarSource(rawValue: raw) {
            return v
        }
        return .auto
    }() {
        didSet { UserDefaults.standard.set(avatarSourcePreference.rawValue, forKey: UD_PROFILE_AVATAR_SOURCE) }
    }

    // Helpers for UI bindings
    var selectedAvatarURL: URL? {
        switch avatarSourcePreference {
        case .auto:
            return avatarURLBluesky ?? avatarURLMastodon
        case .bluesky:
            return avatarURLBluesky
        case .mastodon:
            return avatarURLMastodon
        }
    }

    var selectedHandle: String? {
        switch avatarSourcePreference {
        case .auto:
            return signedInHandleBluesky ?? signedInHandleMastodon
        case .bluesky:
            return signedInHandleBluesky
        case .mastodon:
            return signedInHandleMastodon
        }
    }

    private func isExpiringSoon(_ jwt: String, within seconds: TimeInterval = 300) -> Bool {
        guard let exp = jwtExpirationDate(jwt) else { return false }
        return exp.timeIntervalSinceNow <= seconds
    }

    /// Returns the Bluesky client, refreshing the access token if it is near expiry.
    func blueskyClientEnsuringFreshToken() async -> BlueskyClient? {
        guard isBlueskySignedIn,
              let token = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_TOKEN),
              let pdsString = UserDefaults.standard.string(forKey: UD_BSKY_PDS),
              let pdsURL = URL(string: pdsString)
        else { return blueskyClient }

        if isExpiringSoon(token) {
            let refreshed = await refreshBlueskyIfNeeded()
            if !refreshed {
                // If refresh failed, keep existing client but likely signed out soon.
            }
        } else if blueskyClient == nil {
            blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: token)
        }
        return blueskyClient
    }

    // MARK: - Restore on launch
    func restoreOnLaunch() async {
        // Bluesky
        if let token = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_TOKEN),
           let pdsString = UserDefaults.standard.string(forKey: UD_BSKY_PDS),
           let pdsURL = URL(string: pdsString) {
            // Create a client with the saved token
            blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: token)
            isBlueskySignedIn = true
            signedInHandleBluesky = UserDefaults.standard.string(forKey: UD_BSKY_HANDLE)
            // If the token is expiring soon, refresh immediately
            if isExpiringSoon(token) {
                _ = await refreshBlueskyIfNeeded()
            }
            // Populate identity (DID/handle) for features that require it
            await populateBlueskyIdentityIfNeeded()
            await refreshOwnAvatars()
        }

        // Mastodon
        if let token = Keychain.loadToken(service: KC_SERVICE, account: KC_MASTO_TOKEN),
           let baseString = UserDefaults.standard.string(forKey: UD_MASTO_BASE),
           let baseURL = URL(string: baseString) {
            mastodonClient = MastodonClient(baseURL: baseURL, accessToken: token)
            isMastodonSignedIn = true
            await populateMastodonIdentityIfNeeded()
            await refreshOwnAvatars()
        }
        ensureValidAvatarPreference()
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
        Task { await refreshOwnAvatars() }
    }

    func setMastodonSession(baseURL: URL, accessToken: String) {
        Keychain.save(token: accessToken, service: KC_SERVICE, account: KC_MASTO_TOKEN)
        UserDefaults.standard.set(baseURL.absoluteString, forKey: UD_MASTO_BASE)

        mastodonClient = MastodonClient(baseURL: baseURL, accessToken: accessToken)
        isMastodonSignedIn = true
        // Populate identity in the background for self detection
        Task {
            await populateMastodonIdentityIfNeeded()
            await refreshOwnAvatars()
        }
    }

    // Refresh the cached avatars for signed-in accounts
    func refreshOwnAvatars() async {
        // Bluesky
        if let client = blueskyClient, let handle = signedInHandleBluesky, !handle.isEmpty {
            if let user = try? await client.fetchUserProfile(handle: handle) {
                avatarURLBluesky = user.avatarURL
            }
        }
        // Mastodon
        if let client = mastodonClient, let handle = signedInHandleMastodon, !handle.isEmpty {
            if let user = try? await client.fetchUserProfile(handle: handle) {
                avatarURLMastodon = user.avatarURL
            }
        }
    }

    /// Attempts to refresh the Bluesky session using the saved refresh JWT.
    /// Returns true if a new access token was obtained and the client was updated.
    func refreshBlueskyIfNeeded() async -> Bool {
        guard
            let pdsString = UserDefaults.standard.string(forKey: UD_BSKY_PDS),
            let pdsURL = URL(string: pdsString),
            let refresh = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_REFRESH)
        else { return false }

        // If current access token is still valid, skip
        if let current = Keychain.loadToken(service: KC_SERVICE, account: KC_BSKY_TOKEN),
           isExpiringSoon(current) == false {
            return true
        }

        var url = pdsURL
        url.append(path: "/xrpc/com.atproto.server.refreshSession")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        struct RefreshResp: Decodable { let accessJwt: String; let refreshJwt: String; let handle: String? }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            switch http.statusCode {
            case 200..<300:
                let decoded = try JSONDecoder().decode(RefreshResp.self, from: data)
                // Persist new tokens
                Keychain.save(token: decoded.accessJwt, service: KC_SERVICE, account: KC_BSKY_TOKEN)
                Keychain.save(token: decoded.refreshJwt, service: KC_SERVICE, account: KC_BSKY_REFRESH)
                if let h = decoded.handle { UserDefaults.standard.set(h, forKey: UD_BSKY_HANDLE) }
                // Recreate client with fresh token
                blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: decoded.accessJwt)
                isBlueskySignedIn = true
                if let h = decoded.handle { signedInHandleBluesky = h }
                return true
            case 401, 403:
                // Refresh token invalid/expired — sign out
                signOutBluesky()
                return false
            default:
                return false
            }
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

    private func populateMastodonIdentityIfNeeded() async {
        guard let client = mastodonClient, signedInHandleMastodon == nil else { return }
        var url = client.baseURL; url.append(path: "/api/v1/accounts/verify_credentials")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(client.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        struct MeResp: Decodable { let acct: String }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let me = try JSONDecoder().decode(MeResp.self, from: data)
            signedInHandleMastodon = me.acct
        } catch {
            // ignore errors; handle remains nil
        }
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
        avatarURLBluesky = nil
        if avatarSourcePreference == .bluesky { avatarSourcePreference = .auto }
    }

    func signOutMastodon() {
        mastodonClient = nil
        isMastodonSignedIn = false
        signedInHandleMastodon = nil
        Keychain.delete(service: KC_SERVICE, account: KC_MASTO_TOKEN)
        UserDefaults.standard.removeObject(forKey: UD_MASTO_BASE)
        avatarURLMastodon = nil
        if avatarSourcePreference == .mastodon { avatarSourcePreference = .auto }
    }

    /// Call this before performing an API call to ensure the token is fresh.
    func ensureValidBlueskyAccess() async {
        _ = await blueskyClientEnsuringFreshToken()
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

    private func ensureValidAvatarPreference() {
        switch avatarSourcePreference {
        case .auto:
            break
        case .bluesky:
            if !isBlueskySignedIn { avatarSourcePreference = .auto }
        case .mastodon:
            if !isMastodonSignedIn { avatarSourcePreference = .auto }
        }
    }
}
