import Foundation

extension BlueskyClient {
    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getTimeline"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps?.queryItems = items

        guard let url = comps?.url else { throw URLError(.badURL) }
        let session = try await loadSession()
        let followingDIDs = try await getFollowingSet(actor: session.did)
        let data = try await performGET(url)

        let decoder = makeJSONDecoder()
        let tl: GetTimelineResponse
        do { tl = try decoder.decode(GetTimelineResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }

        let mapped = tl.feed.compactMap { feedItem -> UnifiedPost? in
            let p = feedItem.post
            guard let rec = p.record, rec.type == "app.bsky.feed.post" else { return nil }
            let isRepost = (feedItem.reason?.type == "app.bsky.feed.defs#reasonRepost")
            if !isRepost {
                if let reply = feedItem.reply, let parentAuthor = reply.parent?.author {
                    let followedViaViewer = (parentAuthor.viewer?.following != nil)
                    let followedViaSet = followingDIDs.contains(parentAuthor.did)
                    if !(followedViaViewer || followedViaSet) { return nil }
                } else if feedItem.reply != nil {
                    // Reply context present but no parent author -> drop it
                    return nil
                }
            }
            let boostedHandle = isRepost ? feedItem.reason?.by?.handle : nil
            let boostedName   = isRepost ? feedItem.reason?.by?.displayName : nil
            return mapPostToUnified(p, isRepost: isRepost, boostedByHandle: boostedHandle, boostedByDisplayName: boostedName)
        }
        return (mapped, tl.cursor)
    }

    func fetchThread(root post: UnifiedPost) async throws -> [ThreadItem] {
        guard let uri = post.id.split(separator: ":", maxSplits: 1).last.map(String.init) else { return [] }
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getPostThread"
        comps?.queryItems = [
            URLQueryItem(name: "uri", value: uri),
            URLQueryItem(name: "depth", value: "24"),
            URLQueryItem(name: "parentHeight", value: "12")
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)
        let decoder = makeJSONDecoder()
        let rootResp: GetPostThreadResponse
        do { rootResp = try decoder.decode(GetPostThreadResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }

        var items: [ThreadItem] = []
        if case let .threadViewPost(node) = rootResp.thread {
            if let replies = node.replies { flatten(replies, into: &items, depth: 1) }
        }
        return items
    }

    func fetchAncestors(root post: UnifiedPost) async throws -> [UnifiedPost] {
        guard let uri = post.id.split(separator: ":", maxSplits: 1).last.map(String.init) else { return [] }
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getPostThread"
        comps?.queryItems = [ URLQueryItem(name: "uri", value: uri) ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)
        let decoder = makeJSONDecoder()
        let rootResp: GetPostThreadResponse
        do { rootResp = try decoder.decode(GetPostThreadResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }
        guard case let .threadViewPost(node) = rootResp.thread else { return [] }

        var stack: [UnifiedPost] = []
        var parent = node.parent
        while let p = parent {
            if case let .threadViewPost(pnode) = p {
                stack.append(mapPostToUnified(pnode.post))
                parent = pnode.parent
            } else {
                break
            }
        }
        return stack.reversed()
    }

    func fetchPost(actorOrHandle actor: String, rkey: String) async throws -> UnifiedPost? {
        let did = try await resolveDID(for: actor)
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getPostThread"
        let atUri = "at://\(did)/app.bsky.feed.post/\(rkey)"
        comps?.queryItems = [URLQueryItem(name: "uri", value: atUri)]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)
        let decoder = makeJSONDecoder()
        let resp = try decoder.decode(GetPostThreadResponse.self, from: data)
        if case let .threadViewPost(node) = resp.thread {
            return mapPostToUnified(node.post)
        }
        return nil
    }
}

private extension BlueskyClient {
    struct Session: Decodable { let did: String; let handle: String }
    struct FollowsResponse: Decodable { let cursor: String?; let follows: [BskyProfile] }

    func loadSession() async throws -> Session {
        var sComps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        sComps?.path = "/xrpc/com.atproto.server.getSession"
        guard let sURL = sComps?.url else { throw URLError(.badURL) }
        let data = try await performGET(sURL)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func getFollowingSet(actor did: String, cap: Int = 2000) async throws -> Set<String> {
        var out = Set<String>()
        var next: String? = nil
        repeat {
            var fComps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
            fComps?.path = "/xrpc/app.bsky.graph.getFollows"
            var q = [URLQueryItem(name: "actor", value: did), URLQueryItem(name: "limit", value: "100")]
            if let next { q.append(URLQueryItem(name: "cursor", value: next)) }
            fComps?.queryItems = q
            guard let fURL = fComps?.url else { break }
            let data = try await performGET(fURL)
            let resp = try JSONDecoder().decode(FollowsResponse.self, from: data)
            for p in resp.follows { out.insert(p.did) }
            next = resp.cursor
        } while next != nil && out.count < cap
        return out
    }

    func resolveDID(for actorOrDid: String) async throws -> String {
        if actorOrDid.hasPrefix("did:") { return actorOrDid }
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/com.atproto.identity.resolveHandle"
        comps?.queryItems = [URLQueryItem(name: "handle", value: actorOrDid)]
        guard let url = comps?.url else { throw URLError(.badURL) }
        struct Resp: Decodable { let did: String }
        let data = try await performGET(url)
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return r.did
    }
}
