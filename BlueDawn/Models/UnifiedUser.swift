import Foundation

struct UnifiedUser: Identifiable {
    let id: String
    let network: Network
    let handle: String
    let displayName: String?
    let avatarURL: URL?
    let bio: AttributedString?
    let followersCount: Int?
    let followingCount: Int?
    let postsCount: Int?
    // Following state (if known)
    var isFollowing: Bool? = nil
    // Bluesky-specific: follow record rkey for unfollow
    var bskyFollowRkey: String? = nil
}
