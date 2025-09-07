import Foundation

protocol SocialClient {
    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?)
    /// Replies (descendants) of the root post, flattened with indentation depth.
    func fetchThread(root post: UnifiedPost) async throws -> [ThreadItem]
    /// Ancestors (parent chain) of the root post, oldest → newest (immediate parent last).
    func fetchAncestors(root post: UnifiedPost) async throws -> [UnifiedPost]
    
    func fetchUserProfile(handle: String) async throws -> UnifiedUser
        func fetchAuthorFeed(handle: String, cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?)


    func like(post: UnifiedPost) async throws
    func repost(post: UnifiedPost) async throws
    func reply(to post: UnifiedPost, text: String) async throws
}
