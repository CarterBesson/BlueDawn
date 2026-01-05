import Foundation

extension BlueskyClient {
    struct GetTimelineResponse: Decodable {
        let feed: [FeedViewPost]
        let cursor: String?
    }

    struct FeedViewPost: Decodable {
        let post: Post
        let reply: ReplyRef?
        let reason: Reason?
    }

    struct ReplyRef: Decodable {
        let root: ReplyPost?
        let parent: ReplyPost?
    }

    struct ReplyPost: Decodable {
        let uri: String?
        let cid: String?
        let author: Author?
    }

    struct Reason: Decodable {
        let type: String
        let by: Author?
        enum CodingKeys: String, CodingKey { case type = "$type"; case by }
    }

    struct GetPostThreadResponse: Decodable {
        let thread: ThreadUnion
    }

    indirect enum ThreadUnion: Decodable {
        case threadViewPost(ThreadViewPost)
        case blocked
        case notFound

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch type {
            case "app.bsky.feed.defs#threadViewPost":
                self = .threadViewPost(try ThreadViewPost(from: decoder))
            case "app.bsky.feed.defs#blockedPost":
                self = .blocked
            case "app.bsky.feed.defs#notFoundPost":
                self = .notFound
            default:
                self = .notFound
            }
        }
    }

    class ThreadViewPost: Decodable {
        let post: Post
        let parent: ThreadUnion?
        let replies: [ThreadUnion]?
    }
}
