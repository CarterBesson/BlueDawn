import Foundation

struct PostInteractionState: Hashable {
    var isLiked: Bool
    var isReposted: Bool
    var isBookmarked: Bool
    var likeCount: Int
    var repostCount: Int
    var bskyLikeRkey: String?
    var bskyRepostRkey: String?

    static func fromPost(_ post: UnifiedPost) -> PostInteractionState {
        PostInteractionState(
            isLiked: post.isLiked ?? false,
            isReposted: post.isReposted ?? post.isRepostOrBoost,
            isBookmarked: post.isBookmarked ?? false,
            likeCount: post.counts.favLikes ?? 0,
            repostCount: post.counts.boostsReposts ?? 0,
            bskyLikeRkey: post.bskyLikeRkey,
            bskyRepostRkey: post.bskyRepostRkey
        )
    }
}

