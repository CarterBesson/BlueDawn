import Foundation

extension MastodonClient {
    struct Context: Decodable { let ancestors: [MastoStatus]; let descendants: [MastoStatus] }

    struct MastoStatus: Decodable {
        let id: String
        let created_at: String
        let in_reply_to_id: String?
        let in_reply_to_account_id: String?
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

    struct Account: Decodable {
        let id: String
        let acct: String
        let display_name: String
        let avatar: String
        let note: String?
        let followers_count: Int?
        let following_count: Int?
        let statuses_count: Int?
    }

    struct Relationship: Decodable { let id: String; let following: Bool? }

    struct MastoReblog: Decodable {
        let id: String
        let created_at: String
        let in_reply_to_id: String?
        let sensitive: Bool?
        let spoiler_text: String?
        let content: String
        let account: Account
        let media_attachments: [MediaAttachment]
    }

    struct MediaAttachment: Decodable {
        let id: String
        let type: String
        let url: String
        let preview_url: String?
        let description: String?
    }

    struct VerifyCredentialsResponse: Decodable { let id: String }
}
