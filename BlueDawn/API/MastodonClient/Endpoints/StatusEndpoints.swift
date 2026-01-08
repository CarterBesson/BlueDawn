import Foundation

extension MastodonClient {
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

    func fetchQuotedStatus(host: String, id: String) async throws -> QuotedPost? {
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
}
