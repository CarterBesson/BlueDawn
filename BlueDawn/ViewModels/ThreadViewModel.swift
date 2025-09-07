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
        defer { isLoading = false }

        do {
            let client: SocialClient? = {
                switch root.network {
                case .bluesky:
                    return session.blueskyClient
                case .mastodon(_):
                    return session.mastodonClient
                }
            }()

            guard let client else {
                self.items = []
                self.ancestors = []
                return
            }

            async let repliesTask: [ThreadItem] = client.fetchThread(root: root)
            async let ancestorsTask: [UnifiedPost] = client.fetchAncestors(root: root)

            let (replies, parents) = try await (repliesTask, ancestorsTask)
            self.items = replies
            self.ancestors = parents
        } catch {
            self.error = error.localizedDescription
        }
    }
}
