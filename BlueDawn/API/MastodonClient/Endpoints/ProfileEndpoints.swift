import Foundation

extension MastodonClient {
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
        comps.queryItems = [URLQueryItem(name: "acct", value: acct)]
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
            comps2.queryItems = [URLQueryItem(name: "acct", value: handle)]
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
        var url = baseURL
        url.append(path: "/api/v1/accounts/\(id)/follow")
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
        var url = baseURL
        url.append(path: "/api/v1/accounts/\(id)/unfollow")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
