import Foundation

extension MastodonClient {
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
        async let followInfo = loadFollowingSetIfAvailable()

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let statuses = try JSONDecoder().decode([MastoStatus].self, from: data)
        let followingData = try await followInfo
        let filteredStatuses = filterReplies(statuses, using: followingData)
        var mapped = filteredStatuses.map { mapStatusToUnified($0) }

        // Enrich posts that link to another Mastodon status (same or cross-instance)
        var remainingQuoteFetches = maxQuoteEnrichmentsPerPage
        for i in 0..<min(filteredStatuses.count, mapped.count) {
            if remainingQuoteFetches <= 0 { break }
            if mapped[i].quotedPost == nil, let link = extractLinkedStatus(fromHTML: filteredStatuses[i].content) {
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
        async let followInfo = loadFollowingSetIfAvailable()

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let statuses = try JSONDecoder().decode([MastoStatus].self, from: data)
        let followingData = try await followInfo
        let filteredStatuses = filterReplies(statuses, using: followingData)
        var mapped = filteredStatuses.map { mapStatusToUnified($0) }
        // Enrich quotes in the new batch (bounded)
        var remainingQuoteFetches = maxQuoteEnrichmentsPerPage
        for i in 0..<min(filteredStatuses.count, mapped.count) {
            if remainingQuoteFetches <= 0 { break }
            if mapped[i].quotedPost == nil, let link = extractLinkedStatus(fromHTML: filteredStatuses[i].content) {
                remainingQuoteFetches -= 1
                if let qp = try await fetchQuotedStatus(host: link.host, id: link.id) {
                    mapped[i].quotedPost = qp
                }
            }
        }
        return mapped
    }

    private func loadFollowingSetIfAvailable() async throws -> (selfID: String, following: Set<String>)? {
        guard !accessToken.isEmpty else { return nil }
        let authedID = try await fetchAuthedAccountID()
        let following = try await fetchFollowingSet(accountID: authedID)
        return (authedID, following)
    }

    private func fetchAuthedAccountID() async throws -> String {
        var url = baseURL
        url.append(path: "/api/v1/accounts/verify_credentials")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !accessToken.isEmpty { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let me = try JSONDecoder().decode(VerifyCredentialsResponse.self, from: data)
        return me.id
    }

    private func fetchFollowingSet(accountID: String, cap: Int = 4000) async throws -> Set<String> {
        var out = Set<String>()
        var maxID: String? = nil
        let decoder = JSONDecoder()
        repeat {
            guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { break }
            comps.path = "/api/v1/accounts/\(accountID)/following"
            var queryItems = [URLQueryItem(name: "limit", value: "80")]
            if let maxID { queryItems.append(URLQueryItem(name: "max_id", value: maxID)) }
            comps.queryItems = queryItems
            guard let pageURL = comps.url else { break }
            var req = URLRequest(url: pageURL)
            req.httpMethod = "GET"
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let page = try decoder.decode([Account].self, from: data)
            guard !page.isEmpty else { break }
            for acct in page { out.insert(acct.id) }
            maxID = page.last?.id
        } while maxID != nil && out.count < cap
        return out
    }

    private func filterReplies(_ statuses: [MastoStatus], using info: (selfID: String, following: Set<String>)?) -> [MastoStatus] {
        guard let info = info else { return statuses }
        return statuses.filter { status in
            guard let parentAccountID = status.in_reply_to_account_id else { return true }
            if parentAccountID == info.selfID { return true }
            return info.following.contains(parentAccountID)
        }
    }
}
