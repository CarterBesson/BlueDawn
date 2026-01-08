import Foundation

extension MastodonClient {
    func like(post: UnifiedPost) async throws -> String? {
        guard case .mastodon = post.network else { return nil }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return nil }
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/favourite")
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
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/reblog")
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
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/unfavourite")
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
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/unreblog")
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

    // MARK: - Bookmark
    func bookmark(post: UnifiedPost) async throws {
        guard case .mastodon = post.network else { return }
        guard let id = post.id.split(separator: ":").last.map(String.init) else { return }
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/bookmark")
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
        var url = baseURL
        url.append(path: "/api/v1/statuses/\(id)/unbookmark")
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
