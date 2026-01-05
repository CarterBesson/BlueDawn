import Foundation

struct BlueskyClient: SocialClient {
    let pdsURL: URL // user's PDS base URL (often https://bsky.social)
    let accessToken: String
    var did: String? = nil

    init(pdsURL: URL, accessToken: String, did: String? = nil) {
        self.pdsURL = pdsURL
        self.accessToken = accessToken
        self.did = did
    }
}

extension BlueskyClient {
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

    static func extractRkey(fromAtUri uri: String) -> String? {
        guard let last = uri.split(separator: "/").last else { return nil }
        return String(last)
    }
}
