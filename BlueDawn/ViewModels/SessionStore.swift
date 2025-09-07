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

    // MARK: - Persistence keys
    private let KC_SERVICE = "BlueDawn"

    private let KC_BSKY_TOKEN = "bluesky.token"
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
            blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: token)
            isBlueskySignedIn = true
            signedInHandleBluesky = UserDefaults.standard.string(forKey: UD_BSKY_HANDLE)
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
    func setBlueskySession(pdsURL: URL, accessToken: String, handle: String) {
        Keychain.save(token: accessToken, service: KC_SERVICE, account: KC_BSKY_TOKEN)
        UserDefaults.standard.set(pdsURL.absoluteString, forKey: UD_BSKY_PDS)
        UserDefaults.standard.set(handle, forKey: UD_BSKY_HANDLE)

        blueskyClient = BlueskyClient(pdsURL: pdsURL, accessToken: accessToken)
        isBlueskySignedIn = true
        signedInHandleBluesky = handle
    }

    func setMastodonSession(baseURL: URL, accessToken: String) {
        Keychain.save(token: accessToken, service: KC_SERVICE, account: KC_MASTO_TOKEN)
        UserDefaults.standard.set(baseURL.absoluteString, forKey: UD_MASTO_BASE)

        mastodonClient = MastodonClient(baseURL: baseURL, accessToken: accessToken)
        isMastodonSignedIn = true
    }

    // MARK: - Sign out
    func signOutBluesky() {
        blueskyClient = nil
        isBlueskySignedIn = false
        signedInHandleBluesky = nil
        Keychain.delete(service: KC_SERVICE, account: KC_BSKY_TOKEN)
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
}
