import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var user: UnifiedUser?
    var posts: [UnifiedPost] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    private var nextCursor: String?

    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let network: Network
    @ObservationIgnored private let handle: String

    init(session: SessionStore, network: Network, handle: String) {
        self.session = session
        self.network = network
        self.handle = handle
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let c = client()
            self.user = try await c.fetchUserProfile(handle: handle)
            let (p, cursor) = try await c.fetchAuthorFeed(handle: handle, cursor: nil)
            self.posts = p
            self.nextCursor = cursor
        } catch { self.error = error.localizedDescription }
    }

    func loadMore() async {
        guard !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true; error = nil
        defer { isLoadingMore = false }
        do {
            let (more, next) = try await client().fetchAuthorFeed(handle: handle, cursor: cursor)
            // de-dupe by id
            var seen = Set(posts.map { $0.id })
            let unique = more.filter { seen.insert($0.id).inserted }
            self.posts.append(contentsOf: unique)
            self.nextCursor = next
        } catch { self.error = error.localizedDescription }
    }

    private func client() -> SocialClient {
        switch network {
        case .bluesky:
            precondition(session.blueskyClient != nil, "Not signed into Bluesky")
            return session.blueskyClient!
        case .mastodon(let instance):
            if let c = session.mastodonClient, c.baseURL.host == instance {
                return c
            }
            // Fallback public client for cross-instance profiles (no auth)
            let url = URL(string: "https://\(instance)")!
            return MastodonClient(baseURL: url, accessToken: "")
        }
    }
}
