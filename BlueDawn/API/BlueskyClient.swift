import Foundation

struct BlueskyClient: SocialClient {
    let pdsURL: URL // user's PDS base URL (often https://bsky.social)
    let accessToken: String

    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getTimeline"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps?.queryItems = items

        guard let url = comps?.url else { throw URLError(.badURL) }
        let data = try await performGET(url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tl: GetTimelineResponse
        do { tl = try decoder.decode(GetTimelineResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }

        let mapped = tl.feed.compactMap { feedItem -> UnifiedPost? in
            let p = feedItem.post
            guard let rec = p.record, rec.type == "app.bsky.feed.post" else { return nil }
            let isRepost = (feedItem.reason?.type == "app.bsky.feed.defs#reasonRepost")
            return mapPostToUnified(p, isRepost: isRepost)
        }
        return (mapped, tl.cursor)
    }

    func fetchThread(root post: UnifiedPost) async throws -> [ThreadItem] {
        // Expect post.id like "bsky:<uri>"
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

        let decoder = JSONDecoder()
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
        // Expect post.id like "bsky:<uri>"
        guard let uri = post.id.split(separator: ":", maxSplits: 1).last.map(String.init) else { return [] }
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getPostThread"
        comps?.queryItems = [ URLQueryItem(name: "uri", value: uri) ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let data = try await performGET(url)

        let decoder = JSONDecoder()
        let rootResp: GetPostThreadResponse
        do { rootResp = try decoder.decode(GetPostThreadResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }
        guard case let .threadViewPost(node) = rootResp.thread else { return [] }

        // Walk parent chain up to root; then reverse to oldest → newest
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

    // MARK: - Profile
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
        return UnifiedUser(
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
    }

    // MARK: - Author feed
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
            return mapPostToUnified(p, isRepost: isRepost)
        }
        return (mapped, decoded.cursor)
    }

    func like(post: UnifiedPost) async throws { /* TODO: app.bsky.feed.like */ }
    func repost(post: UnifiedPost) async throws { /* TODO: app.bsky.feed.repost */ }
    func reply(to post: UnifiedPost, text: String) async throws { /* TODO: app.bsky.feed.post */ }

    // MARK: - Request helper
    private func performGET(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.network(URLError(.badServerResponse)) }
            guard (200..<300).contains(http.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8)
                throw APIError.badStatus(http.statusCode, body: bodyStr)
            }
            return data
        } catch let e as URLError {
            throw APIError.network(e)
        } catch {
            throw APIError.unknown(error)
        }
    }

    // MARK: - Flatten helpers
    private func flatten(_ list: [ThreadUnion], into out: inout [ThreadItem], depth: Int) {
        for entry in list {
            switch entry {
            case .threadViewPost(let node):
                let u = mapPostToUnified(node.post)
                out.append(ThreadItem(id: u.id, post: u, depth: depth))
                if let replies = node.replies, !replies.isEmpty {
                    flatten(replies, into: &out, depth: depth + 1)
                }
            default:
                continue
            }
        }
    }

    // MARK: - Mapping
    private func mapPostToUnified(_ p: Post, isRepost: Bool = false) -> UnifiedPost {
        let created = parseISO8601(p.record?.createdAt ?? p.indexedAt ?? "") ?? Date()
        let text = AttributedString(p.record?.text ?? "")
        let media: [Media] = {
            guard let embed = p.embed else { return [] }
            switch embed {
            case .images(let view):
                return view.images.compactMap { img in
                    guard let url = URL(string: img.fullsize ?? img.thumb ?? "") else { return nil }
                    return Media(url: url, altText: img.alt, kind: .image)
                }
            default:
                return []
            }
        }()
        let counts = PostCounts(
            replies: p.replyCount,
            boostsReposts: p.repostCount,
            favLikes: p.likeCount
        )
        return UnifiedPost(
            id: "bsky:\(p.uri)",
            network: .bluesky,
            authorHandle: p.author.handle,
            authorDisplayName: p.author.displayName,
            authorAvatarURL: URL(string: p.author.avatar ?? ""),
            createdAt: created,
            text: text,
            media: media,
            cwOrLabels: nil,
            counts: counts,
            inReplyToID: nil,
            isRepostOrBoost: isRepost
        )
    }

    private func parseISO8601(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: s) ?? f2.date(from: s)
    }

    // MARK: - API models
    enum APIError: LocalizedError {
        case badStatus(Int, body: String?)
        case decoding(DecodingError)
        case network(URLError)
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                if let body,
                   let data = body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = (obj["message"] as? String) ?? (obj["error"] as? String) {
                    return "Bluesky returned \(code): \(message)"
                }
                return "Bluesky returned HTTP \(code)"
            case .decoding:
                return "Couldn’t read data from Bluesky."
            case .network(let e):
                return e.localizedDescription
            case .unknown(let e):
                return e.localizedDescription
            }
        }
    }

    private struct GetTimelineResponse: Decodable {
        let feed: [FeedViewPost]
        let cursor: String?
    }

    private struct FeedViewPost: Decodable {
        let post: Post
        let reason: Reason?
    }

    private struct Reason: Decodable {
        let type: String
        enum CodingKeys: String, CodingKey { case type = "$type" }
    }

    private struct GetPostThreadResponse: Decodable {
        let thread: ThreadUnion
    }

    private indirect enum ThreadUnion: Decodable {
        case threadViewPost(ThreadViewPost)
        case blocked
        case notFound

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch type {
            case "app.bsky.feed.defs#threadViewPost":
                self = .threadViewPost(try ThreadViewPost(from: decoder))
            case "app.bsky.feed.defs#blockedPost":
                self = .blocked
            case "app.bsky.feed.defs#notFoundPost":
                self = .notFound
            default:
                self = .notFound
            }
        }
    }

    // Class to avoid infinite-size recursion with ThreadUnion
    private class ThreadViewPost: Decodable {
        let post: Post
        let parent: ThreadUnion?
        let replies: [ThreadUnion]?
    }

    private struct Post: Decodable {
        let uri: String
        let cid: String
        let author: Author
        let record: Record?
        let embed: Embed?
        let likeCount: Int?
        let replyCount: Int?
        let repostCount: Int?
        let indexedAt: String?
    }

    private struct Author: Decodable {
        let did: String
        let handle: String
        let displayName: String?
        let avatar: String?
    }

    private struct Record: Decodable {
        let type: String
        let text: String
        let createdAt: String
        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case text
            case createdAt
        }
    }

    private enum Embed: Decodable {
        case images(ImagesView)
        case unsupported

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch type {
            case "app.bsky.embed.images#view":
                self = .images(try ImagesView(from: decoder))
            default:
                self = .unsupported
            }
        }
    }

    private struct ImagesView: Decodable {
        let images: [Image]
        struct Image: Decodable {
            let thumb: String?
            let fullsize: String?
            let alt: String?
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    // MARK: - Profile/AuthorFeed models
    private struct BskyProfile: Decodable {
        let did: String
        let handle: String
        let displayName: String?
        let avatar: String?
        let description: String?
        let followersCount: Int?
        let followsCount: Int?
        let postsCount: Int?
    }

    private struct AuthorFeedResponse: Decodable {
        let feed: [FeedViewPost]
        let cursor: String?
    }
}
