import Foundation

struct PostCounts: Codable, Hashable {
    var replies: Int?
    var boostsReposts: Int?
    var favLikes: Int?
}

struct UnifiedPost: Identifiable, Hashable, Codable {
    enum CWOrLabel: Hashable, Codable { case cw(String), label(String) }

    var id: String                // e.g. "mastodon:<id>" or "bsky:<uri>"
    var network: Network
    var authorHandle: String
    var authorDisplayName: String?
    var authorAvatarURL: URL?
    var createdAt: Date
    var text: AttributedString    // Rich text (links/mentions/hashtags)
    var media: [Media]
    var cwOrLabels: [CWOrLabel]?
    var counts: PostCounts
    var inReplyToID: String?
    var isRepostOrBoost: Bool
    // Optional per-network metadata (kept lightweight)
    var bskyCID: String? // For Bluesky like/repost subjects
    var bskyLikeRkey: String? // For Bluesky unlike
    var bskyRepostRkey: String? // For Bluesky unrepost
    // Lightweight interaction state for optimistic UI
    var isLiked: Bool? = false
    var isReposted: Bool? = false
    var isBookmarked: Bool? = false
}
