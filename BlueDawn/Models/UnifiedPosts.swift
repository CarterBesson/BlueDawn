import Foundation

struct PostCounts: Codable, Hashable {
    var replies: Int?
    var boostsReposts: Int?
    var favLikes: Int?
}

struct ThreadPreview: Codable, Hashable {
    let recentReplies: [UnifiedPost] // Most recent 1-2 replies
    let totalReplyCount: Int
    let hasMoreReplies: Bool
    let newestPostDate: Date // Used for timeline positioning
    let conversationParticipants: Set<String> // Handles of participants
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
    // Lightweight interaction state for optimistic UI and server viewer state
    var isLiked: Bool? = false
    var isReposted: Bool? = false
    var isBookmarked: Bool? = false
    // Extras from main branch
    var boostedByHandle: String?
    var boostedByDisplayName: String?
    var crossPostAlternates: [Network: String]? = nil
    var isCrossPostCanonical: Bool = false
    var threadPreview: ThreadPreview? = nil // Set when this is the root of a thread to display
}
