import Foundation

extension BlueskyClient {
    func fetchUserProfile(handle: String) async throws -> UnifiedUser {
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.actor.getProfile"
        comps?.queryItems = [ URLQueryItem(name: "actor", value: handle) ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)

        let prof: BskyProfile
        do { prof = try JSONDecoder().decode(BskyProfile.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }
        let bio = prof.description.flatMap { AttributedString($0) }
        var u = UnifiedUser(
            id: "bsky:\(prof.did)",
            network: .bluesky,
            handle: prof.handle,
            displayName: prof.displayName,
            avatarURL: prof.avatar.flatMap(URL.init(string:)),
            bio: bio,
            followersCount: prof.followersCount,
            followingCount: prof.followsCount,
            postsCount: prof.postsCount
        )
        if let viewer = prof.viewer {
            if let followingUri = viewer.following {
                u.isFollowing = true
                u.bskyFollowRkey = Self.extractRkey(fromAtUri: followingUri)
            } else {
                u.isFollowing = false
                u.bskyFollowRkey = nil
            }
        } else {
            u.isFollowing = nil
            u.bskyFollowRkey = nil
        }
        return u
    }

    func fetchAuthorFeed(handle: String, cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getAuthorFeed"
        var items = [URLQueryItem(name: "actor", value: handle),
                     URLQueryItem(name: "limit", value: "40")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)

        let decoded: AuthorFeedResponse
        do { decoded = try JSONDecoder().decode(AuthorFeedResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }
        let mapped: [UnifiedPost] = decoded.feed.compactMap { item in
            let p = item.post
            guard let rec = p.record, rec.type == "app.bsky.feed.post" else { return nil }
            let isRepost = (item.reason?.type == "app.bsky.feed.defs#reasonRepost")
            let boostedHandle = isRepost ? item.reason?.by?.handle : nil
            let boostedName   = isRepost ? item.reason?.by?.displayName : nil
            return mapPostToUnified(p, isRepost: isRepost, boostedByHandle: boostedHandle, boostedByDisplayName: boostedName)
        }
        return (mapped, decoded.cursor)
    }
}
