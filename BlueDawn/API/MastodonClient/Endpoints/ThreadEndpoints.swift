import Foundation

extension MastodonClient {
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
}
