import Foundation

extension BlueskyClient {
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

    func followUser(did targetDid: String) async throws -> String? {
        guard !targetDid.isEmpty else { return nil }
        guard let repoDid = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.createRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Record: Encodable {
            let type = "app.bsky.graph.follow"
            let subject: String
            let createdAt: String
            enum CodingKeys: String, CodingKey { case subject, createdAt; case type = "$type" }
        }
        struct Body: Encodable { let repo: String; let collection: String; let record: Record }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let body = Body(repo: repoDid, collection: "app.bsky.graph.follow", record: Record(subject: targetDid, createdAt: createdAt))
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

    func unfollowUser(rkey: String) async throws {
        guard let repoDid = did else { throw APIError.unknown(URLError(.userAuthenticationRequired)) }
        var url = pdsURL; url.append(path: "/xrpc/com.atproto.repo.deleteRecord")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let repo: String; let collection: String; let rkey: String }
        let body = Body(repo: repoDid, collection: "app.bsky.graph.follow", rkey: rkey)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)
            throw APIError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
    }
}
