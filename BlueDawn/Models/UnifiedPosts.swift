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

// Lightweight embedded/quoted post used inside a post.
// Intentionally does NOT contain nested quoted/thread fields to avoid recursion.
struct QuotedPost: Codable, Hashable {
    var id: String
    var network: Network
    var authorHandle: String
    var authorDisplayName: String?
    var authorAvatarURL: URL?
    var createdAt: Date
    var text: AttributedString
    var media: [Media]
}

struct UnifiedPost: Identifiable, Codable {
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
    // Quoted/embedded post (Bluesky record embed, Mastodon quote)
    var quotedPost: QuotedPost? = nil
}

// Provide manual Codable to avoid synthesis pitfalls and keep encoding stable
extension UnifiedPost {
    enum CodingKeys: String, CodingKey {
        case id, network, authorHandle, authorDisplayName, authorAvatarURL, createdAt
        case text, media, cwOrLabels, counts, inReplyToID, isRepostOrBoost
        case bskyCID, bskyLikeRkey, bskyRepostRkey
        case isLiked, isReposted, isBookmarked
        case boostedByHandle, boostedByDisplayName
        case crossPostAlternates, isCrossPostCanonical, threadPreview
        case quotedPost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        network = try c.decode(Network.self, forKey: .network)
        authorHandle = try c.decode(String.self, forKey: .authorHandle)
        authorDisplayName = try c.decodeIfPresent(String.self, forKey: .authorDisplayName)
        authorAvatarURL = try c.decodeIfPresent(URL.self, forKey: .authorAvatarURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        text = try c.decode(AttributedString.self, forKey: .text)
        media = try c.decode([Media].self, forKey: .media)
        cwOrLabels = try c.decodeIfPresent([CWOrLabel].self, forKey: .cwOrLabels)
        counts = try c.decode(PostCounts.self, forKey: .counts)
        inReplyToID = try c.decodeIfPresent(String.self, forKey: .inReplyToID)
        isRepostOrBoost = try c.decode(Bool.self, forKey: .isRepostOrBoost)
        bskyCID = try c.decodeIfPresent(String.self, forKey: .bskyCID)
        bskyLikeRkey = try c.decodeIfPresent(String.self, forKey: .bskyLikeRkey)
        bskyRepostRkey = try c.decodeIfPresent(String.self, forKey: .bskyRepostRkey)
        isLiked = try c.decodeIfPresent(Bool.self, forKey: .isLiked)
        isReposted = try c.decodeIfPresent(Bool.self, forKey: .isReposted)
        isBookmarked = try c.decodeIfPresent(Bool.self, forKey: .isBookmarked)
        boostedByHandle = try c.decodeIfPresent(String.self, forKey: .boostedByHandle)
        boostedByDisplayName = try c.decodeIfPresent(String.self, forKey: .boostedByDisplayName)
        crossPostAlternates = try c.decodeIfPresent([Network: String].self, forKey: .crossPostAlternates)
        isCrossPostCanonical = try c.decodeIfPresent(Bool.self, forKey: .isCrossPostCanonical) ?? false
        threadPreview = try c.decodeIfPresent(ThreadPreview.self, forKey: .threadPreview)
        quotedPost = try c.decodeIfPresent(QuotedPost.self, forKey: .quotedPost)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(network, forKey: .network)
        try c.encode(authorHandle, forKey: .authorHandle)
        try c.encodeIfPresent(authorDisplayName, forKey: .authorDisplayName)
        try c.encodeIfPresent(authorAvatarURL, forKey: .authorAvatarURL)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(text, forKey: .text)
        try c.encode(media, forKey: .media)
        try c.encodeIfPresent(cwOrLabels, forKey: .cwOrLabels)
        try c.encode(counts, forKey: .counts)
        try c.encodeIfPresent(inReplyToID, forKey: .inReplyToID)
        try c.encode(isRepostOrBoost, forKey: .isRepostOrBoost)
        try c.encodeIfPresent(bskyCID, forKey: .bskyCID)
        try c.encodeIfPresent(bskyLikeRkey, forKey: .bskyLikeRkey)
        try c.encodeIfPresent(bskyRepostRkey, forKey: .bskyRepostRkey)
        try c.encodeIfPresent(isLiked, forKey: .isLiked)
        try c.encodeIfPresent(isReposted, forKey: .isReposted)
        try c.encodeIfPresent(isBookmarked, forKey: .isBookmarked)
        try c.encodeIfPresent(boostedByHandle, forKey: .boostedByHandle)
        try c.encodeIfPresent(boostedByDisplayName, forKey: .boostedByDisplayName)
        try c.encodeIfPresent(crossPostAlternates, forKey: .crossPostAlternates)
        try c.encode(isCrossPostCanonical, forKey: .isCrossPostCanonical)
        try c.encodeIfPresent(threadPreview, forKey: .threadPreview)
        try c.encodeIfPresent(quotedPost, forKey: .quotedPost)
    }
}

// Provide manual Equatable/Hashable to avoid recursive synthesis
extension UnifiedPost {
    static func == (lhs: UnifiedPost, rhs: UnifiedPost) -> Bool { lhs.id == rhs.id }
}

extension UnifiedPost: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
