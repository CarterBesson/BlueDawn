import Foundation

extension BlueskyClient {
    struct BskyProfile: Decodable {
        let did: String
        let handle: String
        let displayName: String?
        let avatar: String?
        let description: String?
        let followersCount: Int?
        let followsCount: Int?
        let postsCount: Int?
        let viewer: ProfileViewer?
        struct ProfileViewer: Decodable { let following: String? }
    }

    struct AuthorFeedResponse: Decodable {
        let feed: [FeedViewPost]
        let cursor: String?
    }
}
