import Foundation

struct MastodonClient: SocialClient {
    let baseURL: URL // e.g., https://mastodon.social
    let accessToken: String
    private let maxQuoteEnrichmentsPerPage = 6

    // MARK: Home timeline
    func fetchHomeTimeline(cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.path = "/api/v1/timelines/home"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let cursor = cursor { items.append(URLQueryItem(name: "max_id", value: cursor)) }
        comps.queryItems = items
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let statuses = try JSONDecoder().decode([MastoStatus].self, from: data)
        var mapped = statuses.map { mapStatusToUnified($0) }

        // Enrich posts that link to another Mastodon status (same or cross-instance)
        var remainingQuoteFetches = maxQuoteEnrichmentsPerPage
        for i in 0..<min(statuses.count, mapped.count) {
            if remainingQuoteFetches <= 0 { break }
            if mapped[i].quotedPost == nil, let link = extractLinkedStatus(fromHTML: statuses[i].content) {
                remainingQuoteFetches -= 1
                if let qp = try await fetchQuotedStatus(host: link.host, id: link.id) {
                    mapped[i].quotedPost = qp
                }
            }
        }
        let nextCursor = statuses.last?.id
        return (mapped, nextCursor)
    }

    // Fetch newer statuses than the given since_id (Mastodon supports this natively).
    // Returns newest-first posts and does not include the since_id item itself.
    func fetchHomeTimelineSince(sinceID: String) async throws -> [UnifiedPost] {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.path = "/api/v1/timelines/home"
        // Mastodon returns newest-first by default; using since_id will fetch items with id > since_id
        comps.queryItems = [
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "since_id", value: sinceID)
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let statuses = try JSONDecoder().decode([MastoStatus].self, from: data)
        var mapped = statuses.map { mapStatusToUnified($0) }
        // Enrich quotes in the new batch (bounded)
        var remainingQuoteFetches = maxQuoteEnrichmentsPerPage
        for i in 0..<min(statuses.count, mapped.count) {
            if remainingQuoteFetches <= 0 { break }
            if mapped[i].quotedPost == nil, let link = extractLinkedStatus(fromHTML: statuses[i].content) {
                remainingQuoteFetches -= 1
                if let qp = try await fetchQuotedStatus(host: link.host, id: link.id) {
                    mapped[i].quotedPost = qp
                }
            }
        }
        return mapped
    }

    // Try to find a linked Mastodon status URL in the content HTML.
    // Supports patterns like:
    //  - https://example.org/@user/123456789
    //  - https://example.org/users/user/statuses/123456789
    private func extractLinkedStatus(fromHTML html: String) -> (host: String, id: String)? {
        // Very light anchor HREF extraction
        let pattern = #"<a[^>]+href=\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.numberOfRanges < 2 { continue }
            let urlStr = ns.substring(with: m.range(at: 1))
            guard let url = URL(string: urlStr) else { continue }
            guard let host = url.host else { continue }
            let comps = url.pathComponents.filter { $0 != "/" }
            // Patterns: /@user/<id> OR /users/<acct>/statuses/<id>
            if let last = comps.last, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: last)) {
                return (host, last)
            }
            if let idx = comps.firstIndex(of: "statuses"), idx + 1 < comps.count {
                let cand = comps[idx + 1]
                if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cand)) {
                    return (host, cand)
                }
            }
        }
        return nil
    }

    private func fetchQuotedStatus(host: String, id: String) async throws -> QuotedPost? {
        var comps = URLComponents()
        comps.scheme = baseURL.scheme
        comps.host = host
        comps.path = "/api/v1/statuses/\(id)"
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Public fetch; do not attach Authorization for remote hosts
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let s = try? JSONDecoder().decode(MastoStatus.self, from: data) else { return nil }
        return mapStatusToQuoted(s, instanceHost: host)
    }

    // MARK: Thread replies (descendants)
    func fetchThread(root post: UnifiedPost) async throws -> [ThreadItem] {
        // post.id like "mastodon:<id>"
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return [] }
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/context")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let context = try JSONDecoder().decode(Context.self, from: data)

        // build id -> status for depth calculation
        let all = context.descendants
        var byID: [String: MastoStatus] = [:]
        for s in all { byID[s.id] = s }

        func depth(for s: MastoStatus) -> Int {
            var d = 1
            var parent = s.in_reply_to_id
            var guardCounter = 0
            while let pid = parent, pid != id, guardCounter < 32 {
                if let p = byID[pid] { d += 1; parent = p.in_reply_to_id } else { break }
                guardCounter += 1
            }
            return d
        }

        let sorted = all.sorted { parseISO8601($0.created_at) ?? .distantPast < parseISO8601($1.created_at) ?? .distantPast }
        return sorted.map { s in
            let u = mapStatusToUnified(s)
            return ThreadItem(id: u.id, post: u, depth: depth(for: s))
        }
    }

    // MARK: - Single status fetch (public)
    /// Fetch a single status by id from this client's baseURL and map to UnifiedPost.
    func fetchStatus(id: String) async throws -> UnifiedPost? {
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let s = try? JSONDecoder().decode(MastoStatus.self, from: data) else { return nil }
        return mapStatusToUnified(s)
    }

    // MARK: Thread ancestors (parents)
    func fetchAncestors(root post: UnifiedPost) async throws -> [UnifiedPost] {
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return [] }
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/context")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let context = try JSONDecoder().decode(Context.self, from: data)
        let sorted = context.ancestors.sorted { parseISO8601($0.created_at) ?? .distantPast < parseISO8601($1.created_at) ?? .distantPast }
        return sorted.map { mapStatusToUnified($0) }
    }

    func like(post: UnifiedPost) async throws -> String? {
        guard case .mastodon = post.network else { return nil }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return nil }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/favourite")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return nil
    }

    func repost(post: UnifiedPost) async throws -> String? {
        guard case .mastodon = post.network else { return nil }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return nil }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/reblog")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return nil
    }
    
    func unlike(post: UnifiedPost, rkey: String?) async throws {
        guard case .mastodon = post.network else { return }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/unfavourite")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    func unrepost(post: UnifiedPost, rkey: String?) async throws {
        guard case .mastodon = post.network else { return }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/unreblog")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    func reply(to post: UnifiedPost, text: String) async throws { /* TODO: POST /api/v1/statuses */ }

    // MARK: - Profile
    func fetchUserProfile(handle: String) async throws -> UnifiedUser {
        let acct = try await lookupAccount(handle: handle)
        let bio = htmlToAttributed(acct.note ?? "")
        var user = UnifiedUser(
            id: "mastodon:\(acct.id)",
            network: .mastodon(instance: baseURL.host ?? baseURL.absoluteString),
            handle: acct.acct,
            displayName: acct.display_name.isEmpty ? nil : acct.display_name,
            avatarURL: URL(string: acct.avatar),
            bio: bio,
            followersCount: acct.followers_count,
            followingCount: acct.following_count,
            postsCount: acct.statuses_count
        )
        // If authenticated, fetch relationship to determine follow state
        if !accessToken.isEmpty {
            if let rel = try? await relationship(id: acct.id) {
                user.isFollowing = rel.following
            }
        }
        return user
    }

    // MARK: - Author feed
    func fetchAuthorFeed(handle: String, cursor: String?) async throws -> (posts: [UnifiedPost], nextCursor: String?) {
        let acct = try await lookupAccount(handle: handle)

        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        comps.path = "/api/v1/accounts/\(acct.id)/statuses"
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let cursor = cursor { items.append(URLQueryItem(name: "max_id", value: cursor)) }
        comps.queryItems = items
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let statuses = try JSONDecoder().decode([MastoStatus].self, from: data)
        var mapped = statuses.map { mapStatusToUnified($0) }
        var remainingQuoteFetches = maxQuoteEnrichmentsPerPage
        for i in 0..<min(statuses.count, mapped.count) {
            if remainingQuoteFetches <= 0 { break }
            if mapped[i].quotedPost == nil, let link = extractLinkedStatus(fromHTML: statuses[i].content) {
                remainingQuoteFetches -= 1
                if let qp = try await fetchQuotedStatus(host: link.host, id: link.id) {
                    mapped[i].quotedPost = qp
                }
            }
        }
        let next = statuses.last?.id
        return (mapped, next)
    }

    // Helper to resolve an account by handle
    private func lookupAccount(handle: String) async throws -> Account {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        comps.path = "/api/v1/accounts/lookup"
        // If handle includes @domain matching this instance, strip it for reliability
        let acct: String = {
            if let at = handle.firstIndex(of: "@") {
                let name = String(handle[..<at])
                let domain = String(handle[handle.index(after: at)...])
                if domain == (baseURL.host ?? domain) { return name }
            }
            return handle
        }()
        comps.queryItems = [ URLQueryItem(name: "acct", value: acct) ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return try JSONDecoder().decode(Account.self, from: data)
        } catch {
            // Fallback: try with full acct including domain if initial stripped form failed
            if acct == handle { throw error }
            var comps2 = comps
            comps2.queryItems = [ URLQueryItem(name: "acct", value: handle) ]
            guard let url2 = comps2.url else { throw URLError(.badURL) }
            var req2 = URLRequest(url: url2)
            req2.httpMethod = "GET"
            if !accessToken.isEmpty { req2.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
            req2.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data2, resp2) = try await URLSession.shared.data(for: req2)
            guard let http2 = resp2 as? HTTPURLResponse, (200..<300).contains(http2.statusCode) else {
                throw APIError.badStatus((resp2 as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return try JSONDecoder().decode(Account.self, from: data2)
        }
    }

    // MARK: - Mapping helpers
    private func mapStatusToUnified(_ s: MastoStatus) -> UnifiedPost {
        // Prefer the boosted/original content when this status is a reblog
        let src = s.reblog ?? MastoReblog(
            id: s.id,
            created_at: s.created_at,
            in_reply_to_id: s.in_reply_to_id,
            sensitive: s.sensitive,
            spoiler_text: s.spoiler_text,
            content: s.content,
            account: s.account,
            media_attachments: s.media_attachments
        )
        let isBoost = (s.reblog != nil)
        let boostedName = isBoost ? (s.account.display_name.isEmpty ? nil : s.account.display_name) : nil
        let boostedHandle = isBoost ? s.account.acct : nil

        let created = parseISO8601(src.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(src.content)
        let media: [Media] = src.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        let cwLabels: [UnifiedPost.CWOrLabel]? = {
            var arr: [UnifiedPost.CWOrLabel] = []
            if let spoiler = src.spoiler_text, !spoiler.isEmpty { arr.append(.cw(spoiler)) }
            if src.sensitive == true { arr.append(.label("sensitive")) }
            return arr.isEmpty ? nil : arr
        }()

        // Quoted post (if present)
        let quoted: QuotedPost? = {
            if let q = s.quote { return mapReblogToQuoted(q) }
            return nil
        }()

        return UnifiedPost(
            id: "mastodon:\(src.id)",
            network: .mastodon(instance: baseURL.host ?? baseURL.absoluteString),
            authorHandle: src.account.acct,
            authorDisplayName: src.account.display_name.isEmpty ? nil : src.account.display_name,
            authorAvatarURL: URL(string: src.account.avatar),
            createdAt: created,
            text: text,
            media: media,
            cwOrLabels: cwLabels,
            counts: PostCounts(replies: s.replies_count, boostsReposts: s.reblogs_count, favLikes: s.favourites_count),
            inReplyToID: src.in_reply_to_id,
            isRepostOrBoost: isBoost,
            bskyCID: nil,
            isLiked: s.favourited ?? false,
            isReposted: s.reblogged ?? false,
            isBookmarked: s.bookmarked ?? false,
            boostedByHandle: boostedHandle,
            boostedByDisplayName: boostedName,
            quotedPost: quoted
        )
    }

    // Map a full status to a compact quoted post (no nested quotes/thread fields)
    private func mapStatusToQuoted(_ s: MastoStatus, instanceHost: String? = nil) -> QuotedPost {
        let created = parseISO8601(s.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(s.content)
        let media: [Media] = s.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        return QuotedPost(
            id: "mastodon:\(s.id)",
            network: .mastodon(instance: instanceHost ?? (baseURL.host ?? baseURL.absoluteString)),
            authorHandle: s.account.acct,
            authorDisplayName: s.account.display_name.isEmpty ? nil : s.account.display_name,
            authorAvatarURL: URL(string: s.account.avatar),
            createdAt: created,
            text: text,
            media: media
        )
    }
    
    private func mapReblogToQuoted(_ src: MastoReblog) -> QuotedPost {
        let created = parseISO8601(src.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(src.content)
        let media: [Media] = src.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        return QuotedPost(
            id: "mastodon:\(src.id)",
            network: .mastodon(instance: baseURL.host ?? baseURL.absoluteString),
            authorHandle: src.account.acct,
            authorDisplayName: src.account.display_name.isEmpty ? nil : src.account.display_name,
            authorAvatarURL: URL(string: src.account.avatar),
            createdAt: created,
            text: text,
            media: media
        )
    }

    // very light HTML→plain text conversion (avoids UIKit dependency)
    private func htmlToAttributed(_ html: String) -> AttributedString {
        let withBreaks = html.replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return AttributedString(stripped)
    }

    private func parseISO8601(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: s) ?? f2.date(from: s)
    }

    // MARK: - API models
    private enum APIError: Error { case badStatus(Int) }

    private struct Context: Decodable { let ancestors: [MastoStatus]; let descendants: [MastoStatus] }

    private struct MastoStatus: Decodable {
        let id: String
        let created_at: String
        let in_reply_to_id: String?
        let sensitive: Bool?
        let spoiler_text: String?
        let content: String
        let account: Account
        let media_attachments: [MediaAttachment]
        let reblog: MastoReblog?
        // Optional quoted post support (Mastodon 4.2+ on some servers)
        let quote: MastoReblog?
        let quote_id: String?
        let replies_count: Int?
        let reblogs_count: Int?
        let favourites_count: Int?
        let reblogged: Bool?
        let favourited: Bool?
        let bookmarked: Bool?
    }

    private struct Account: Decodable {
        let id: String
        let acct: String
        let display_name: String
        let avatar: String
        let note: String?
        let followers_count: Int?
        let following_count: Int?
        let statuses_count: Int?
    }

    private struct Relationship: Decodable { let id: String; let following: Bool? }

    private func relationship(id: String) async throws -> Relationship? {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        comps?.path = "/api/v1/accounts/relationships"
        comps?.queryItems = [URLQueryItem(name: "id[]", value: id)]
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let arr = try JSONDecoder().decode([Relationship].self, from: data)
        return arr.first
    }

    // MARK: - Follow / Unfollow
    func followUser(id: String) async throws {
        var url = baseURL; url.append(path: "/api/v1/accounts/\(id)/follow")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    func unfollowUser(id: String) async throws {
        var url = baseURL; url.append(path: "/api/v1/accounts/\(id)/unfollow")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private struct MastoReblog: Decodable {
        let id: String
        let created_at: String
        let in_reply_to_id: String?
        let sensitive: Bool?
        let spoiler_text: String?
        let content: String
        let account: Account
        let media_attachments: [MediaAttachment]
    }

    private struct MediaAttachment: Decodable { let id: String; let type: String; let url: String; let preview_url: String?; let description: String? }

    // MARK: - Bookmark
    func bookmark(post: UnifiedPost) async throws {
        guard case .mastodon = post.network else { return }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/bookmark")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    func unbookmark(post: UnifiedPost) async throws {
        guard case .mastodon = post.network else { return }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return }
        var url = baseURL; url.append(path: "/api/v1/statuses/\(id)/unbookmark")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
