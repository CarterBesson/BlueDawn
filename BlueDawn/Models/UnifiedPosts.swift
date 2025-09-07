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
}
