import Foundation

struct MastodonClient: SocialClient {
    let baseURL: URL // e.g., https://mastodon.social
    let accessToken: String
    private let maxQuoteEnrichmentsPerPage = 6
}

extension MastodonClient {
    enum APIError: Error { case badStatus(Int) }
}
