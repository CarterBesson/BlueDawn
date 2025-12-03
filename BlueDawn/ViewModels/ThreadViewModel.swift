import Foundation
import Observation

@MainActor
@Observable
final class ThreadViewModel {
    // Observed state
    var items: [ThreadItem] = []
    var ancestors: [UnifiedPost] = []
    var isLoading: Bool = false
    var error: String? = nil
    var didInsertAncestors: Bool = false

    // Non-observed dependencies
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let root: UnifiedPost

    init(session: SessionStore, root: UnifiedPost) {
        self.session = session
        self.root = root
    }

    func load() async {
        isLoading = true
        error = nil
        self.didInsertAncestors = false
        defer { isLoading = false }

        do {
            if case .bluesky = root.network {
                await session.ensureValidBlueskyAccess()
            }

            let client: SocialClient? = clientFor(root)

            guard let client else {
                self.items = []
                self.ancestors = []
                return
            }

            async let repliesTask: [ThreadItem] = client.fetchThread(root: root)
            async let ancestorsTask: [UnifiedPost] = client.fetchAncestors(root: root)

            let parents = try await ancestorsTask
            self.ancestors = parents
            self.didInsertAncestors = true

            let replies = try await repliesTask
            self.items = replies
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension ThreadViewModel {
    func clientFor(_ post: UnifiedPost) -> SocialClient? {
        switch post.network {
        case .bluesky:
            return session.blueskyClient
        case .mastodon(let instance):
            if let c = session.mastodonClient, c.baseURL.host == instance {
                return c
            }
            // Fallback to a public client for the post's instance
            guard let url = URL(string: "https://\(instance)") else { return nil }
            return MastodonClient(baseURL: url, accessToken: "")
        }
    }
}
