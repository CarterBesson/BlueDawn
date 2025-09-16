import Foundation

protocol SocialClient {
    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?)
    /// Replies (descendants) of the root post, flattened with indentation depth.
    func fetchThread(root post: UnifiedPost) async throws -> [ThreadItem]
    /// Ancestors (parent chain) of the root post, oldest → newest (immediate parent last).
    func fetchAncestors(root post: UnifiedPost) async throws -> [UnifiedPost]
    
    func fetchUserProfile(handle: String) async throws -> UnifiedUser
        func fetchAuthorFeed(handle: String, cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?)


    /// Returns a token/rkey to support undo when applicable (e.g., Bluesky).
    func like(post: UnifiedPost) async throws -> String?
    func repost(post: UnifiedPost) async throws -> String?
    func unlike(post: UnifiedPost, rkey: String?) async throws
    func unrepost(post: UnifiedPost, rkey: String?) async throws
    func reply(to post: UnifiedPost, text: String) async throws
    /// Optional: only supported on Mastodon. Other services may throw unsupported.
    func bookmark(post: UnifiedPost) async throws
    func unbookmark(post: UnifiedPost) async throws
}

extension SocialClient {
    // Default implementation for services that don't support bookmarks
    func bookmark(post: UnifiedPost) async throws { /* no-op by default */ }
    func unbookmark(post: UnifiedPost) async throws { /* no-op by default */ }
}
