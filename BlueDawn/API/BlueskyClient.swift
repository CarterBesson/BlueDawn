import Foundation

struct BlueskyClient: SocialClient {
    let pdsURL: URL // user's PDS base URL (often https://bsky.social)
    let accessToken: String
    var did: String? = nil

    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        var comps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
        comps?.path = "/xrpc/app.bsky.feed.getTimeline"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        comps?.queryItems = items

        guard let url = comps?.url else { throw URLError(.badURL) }
        // Load the authed user's DID and their following DIDs so we can filter replies reliably
        struct Session: Decodable { let did: String; let handle: String }
        func getSession() async throws -> Session {
            var sComps = URLComponents(url: pdsURL, resolvingAgainstBaseURL: false)
            sComps?.path = "/xrpc/com.atproto.server.getSession"
            guard let sURL = sComps?.url else { throw URLError(.badURL) }
            let data = try await performGET(sURL)
            return try JSONDecoder().decode(Session.self, from: data)
        }
        struct FollowsResponse: Decodable { let cursor: String?; let follows: [BskyProfile] }
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
        let session = try await getSession()
        let followingDIDs = try await getFollowingSet(actor: session.did)
        let data = try await performGET(url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tl: GetTimelineResponse
        do { tl = try decoder.decode(GetTimelineResponse.self, from: data) }
        catch let e as DecodingError { throw APIError.decoding(e) }

        let mapped = tl.feed.compactMap { feedItem -> UnifiedPost? in
            let p = feedItem.post
            guard let rec = p.record, rec.type == "app.bsky.feed.post" else { return nil }
            // Exclude replies unless they are to authors I follow
            if let r = p.reply, let parentAuthor = r.parent?.author {
                let followedViaViewer = (parentAuthor.viewer?.following != nil)
                let followedViaSet = followingDIDs.contains(parentAuthor.did)
                if !(followedViaViewer || followedViaSet) { return nil }
            }
            let isRepost = (feedItem.reason?.type == "app.bsky.feed.defs#reasonRepost")
            let boostedHandle = isRepost ? feedItem.reason?.by?.handle : nil
            let boostedName   = isRepost ? feedItem.reason?.by?.displayName : nil
            return mapPostToUnified(p, isRepost: isRepost, boostedByHandle: boostedHandle, boostedByDisplayName: boostedName)
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
            let boostedHandle = isRepost ? item.reason?.by?.handle : nil
            let boostedName   = isRepost ? item.reason?.by?.displayName : nil
            return mapPostToUnified(p, isRepost: isRepost, boostedByHandle: boostedHandle, boostedByDisplayName: boostedName)
        }
        return (mapped, decoded.cursor)
    }

    func like(post: UnifiedPost) async throws -> String? {
        guard case .bluesky = post.network else { return nil }
        guard let did = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        guard let uri = post.id.split(separator: ":", maxSplits: 1).last.map(String.init),
              let cid = post.bskyCID else { throw APIError.unknown(URLError(.badURL)) }

        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.createRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Subject: Encodable { let uri: String; let cid: String }
        struct Record: Encodable {
            let type = "app.bsky.feed.like"
            let subject: Subject
            let createdAt: String
            enum CodingKeys: String, CodingKey { case subject, createdAt; case type = "$type" }
        }
        struct Body: Encodable { let repo: String; let collection: String; let record: Record }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let body = Body(repo: did, collection: "app.bsky.feed.like", record: Record(subject: .init(uri: uri, cid: cid), createdAt: createdAt))
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
        struct CreateResp: Decodable { let uri: String }
        if let decoded = try? JSONDecoder().decode(CreateResp.self, from: data) {
            return Self.extractRkey(fromAtUri: decoded.uri)
        }
        return nil
    }

    func repost(post: UnifiedPost) async throws -> String? {
        guard case .bluesky = post.network else { return nil }
        guard let did = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        guard let uri = post.id.split(separator: ":", maxSplits: 1).last.map(String.init),
              let cid = post.bskyCID else { throw APIError.unknown(URLError(.badURL)) }

        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.createRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Subject: Encodable { let uri: String; let cid: String }
        struct Record: Encodable {
            let type = "app.bsky.feed.repost"
            let subject: Subject
            let createdAt: String
            enum CodingKeys: String, CodingKey { case subject, createdAt; case type = "$type" }
        }
        struct Body: Encodable { let repo: String; let collection: String; let record: Record }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let body = Body(repo: did, collection: "app.bsky.feed.repost", record: Record(subject: .init(uri: uri, cid: cid), createdAt: createdAt))
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
        struct CreateResp: Decodable { let uri: String }
        if let decoded = try? JSONDecoder().decode(CreateResp.self, from: data) {
            return Self.extractRkey(fromAtUri: decoded.uri)
        }
        return nil
    }

    func unlike(post: UnifiedPost, rkey: String?) async throws {
        guard case .bluesky = post.network else { return }
        guard let did = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        let rkeyToUse = rkey ?? post.bskyLikeRkey
        guard let rkeyToUse else { throw APIError.unknown(URLError(.badURL)) }

        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.deleteRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let repo: String; let collection: String; let rkey: String }
        let body = Body(repo: did, collection: "app.bsky.feed.like", rkey: rkeyToUse)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
    }

    func unrepost(post: UnifiedPost, rkey: String?) async throws {
        guard case .bluesky = post.network else { return }
        guard let did = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        let rkeyToUse = rkey ?? post.bskyRepostRkey
        guard let rkeyToUse else { throw APIError.unknown(URLError(.badURL)) }

        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.deleteRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let repo: String; let collection: String; let rkey: String }
        let body = Body(repo: did, collection: "app.bsky.feed.repost", rkey: rkeyToUse)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
    }
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

    // MARK: - Rich text helpers (links from facets + fallback detection)
    private func indexAtByteOffset(_ byteOffset: Int, in s: String) -> String.Index? {
        var i = s.startIndex
        var b = 0
        while true {
            if b == byteOffset { return i }
            guard i < s.endIndex else { break }
            b += s[i].utf8.count
            i = s.index(after: i)
        }
        return nil
    }

    private func attributedFromBsky(text raw: String, facets: [Facet]?) -> AttributedString {
        var attr = AttributedString(raw)

        // Apply links from facets (http links and mentions)
        if let facets {
            for f in facets {
                guard let s = indexAtByteOffset(f.index.byteStart, in: raw),
                      let e = indexAtByteOffset(f.index.byteEnd, in: raw), s <= e else { continue }

                let lowerChars = raw.distance(from: raw.startIndex, to: s)
                let upperChars = raw.distance(from: raw.startIndex, to: e)
                let lower = attr.characters.index(attr.startIndex, offsetBy: lowerChars)
                let upper = attr.characters.index(attr.startIndex, offsetBy: upperChars)

                for feature in f.features {
                    switch feature {
                    case .link(let uri):
                        if let url = URL(string: uri) {
                            attr[lower..<upper].link = url
                        }
                    case .mention:
                        // Build an internal link that encodes the visible handle (e.g., @alice.bsky.social)
                        let visible = String(raw[s..<e])
                        let handle = visible.hasPrefix("@") ? String(visible.dropFirst()) : visible
                        if let url = URL(string: "bluesky://profile/\(handle)") {
                            attr[lower..<upper].link = url
                        }
                    default:
                        continue
                    }
                }
            }
        }

        // Fallback: detect http(s) links when no facet present
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = raw as NSString
            let matches = detector.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches {
                guard let url = m.url, let r = Range(m.range, in: raw) else { continue }
                let lowerChars = raw.distance(from: raw.startIndex, to: r.lowerBound)
                let upperChars = raw.distance(from: raw.startIndex, to: r.upperBound)
                let lower = attr.characters.index(attr.startIndex, offsetBy: lowerChars)
                let upper = attr.characters.index(attr.startIndex, offsetBy: upperChars)
                if attr[lower..<upper].link == nil { // don't overwrite facet links
                    attr[lower..<upper].link = url
                }
            }
        }
        return attr
    }

    // MARK: - Mapping
    private func mapPostToUnified(_ p: Post, isRepost: Bool = false, boostedByHandle: String? = nil, boostedByDisplayName: String? = nil) -> UnifiedPost {
        let created = parseISO8601(p.record?.createdAt ?? p.indexedAt ?? "") ?? Date()
        let text = attributedFromBsky(text: p.record?.text ?? "", facets: p.record?.facets)
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
        let (isLiked, likeRkey): (Bool, String?) = {
            if let likeUri = p.viewer?.like, let r = Self.extractRkey(fromAtUri: likeUri) { return (true, r) }
            return (false, nil)
        }()
        let (isReposted, repostRkey): (Bool, String?) = {
            if let rpUri = p.viewer?.repost, let r = Self.extractRkey(fromAtUri: rpUri) { return (true, r) }
            return (false, nil)
        }()

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
            isRepostOrBoost: isRepost,
            bskyCID: p.cid,
            bskyLikeRkey: likeRkey,
            bskyRepostRkey: repostRkey,
            isLiked: isLiked,
            isReposted: isReposted,
            isBookmarked: false,
            boostedByHandle: boostedByHandle,
            boostedByDisplayName: boostedByDisplayName
        )
    }

    private static func extractRkey(fromAtUri uri: String) -> String? {
        // at://did:.../collection/rkey
        guard let last = uri.split(separator: "/").last else { return nil }
        return String(last)
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
        let by: Author?
        enum CodingKeys: String, CodingKey { case type = "$type"; case by }
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
        let viewer: Viewer?
        // Reply context from app.bsky.feed.defs#postView
        let reply: ReplyContext?

        enum CodingKeys: String, CodingKey {
            case uri, cid, author, record, embed, likeCount, replyCount, repostCount, indexedAt
            case viewer
            case reply
        }

        struct ReplyContext: Decodable {
            let parent: ReplyPost?
            let root: ReplyPost?
        }
        struct ReplyPost: Decodable { let author: Author }
    }

    private struct Viewer: Decodable {
        let like: String?
        let repost: String?
    }

    private struct Author: Decodable {
        let did: String
        let handle: String
        let displayName: String?
        let avatar: String?
        let viewer: Viewer?                 // present when API includes viewer info

        struct Viewer: Decodable {          // non-nil `following` means you follow them
            let following: String?
        }
    }

    private struct Record: Decodable {
        let type: String
        let text: String
        let createdAt: String
        let facets: [Facet]?            // NEW
        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case text
            case createdAt
            case facets
        }
    }

    private struct Facet: Decodable {
        let index: FacetIndex
        let features: [Feature]
        struct FacetIndex: Decodable { let byteStart: Int; let byteEnd: Int }
    }

    private enum Feature: Decodable {
        case link(uri: String)
        case mention(did: String)
        case tag(tag: String)
        case unknown

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let t = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch t {
            case "app.bsky.richtext.facet#link":
                struct L: Decodable { let uri: String }
                self = .link(uri: try L(from: decoder).uri)
            case "app.bsky.richtext.facet#mention":
                struct M: Decodable { let did: String }
                self = .mention(did: try M(from: decoder).did)
            case "app.bsky.richtext.facet#tag":
                struct T: Decodable { let tag: String }
                self = .tag(tag: try T(from: decoder).tag)
            default:
                self = .unknown
            }
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
