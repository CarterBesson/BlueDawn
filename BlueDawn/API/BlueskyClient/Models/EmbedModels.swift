import Foundation

extension BlueskyClient {
    struct Post: Decodable {
        let uri: String
        let cid: String
        let author: Author
        let record: Record?
        let embed: Embed?
        let likeCount: Int?
        let replyCount: Int?
        let repostCount: Int?
        let indexedAt: String?
        let viewer: Viewer?
        let reply: ReplyContext?

        enum CodingKeys: String, CodingKey {
            case uri, cid, author, record, embed, likeCount, replyCount, repostCount, indexedAt
            case viewer
            case reply
        }

        struct ReplyContext: Decodable {
            let parent: ReplyPost?
            let root: ReplyPost?
        }

        struct ReplyPost: Decodable { let author: Author }
    }

    struct Viewer: Decodable {
        let like: String?
        let repost: String?
    }

    struct Author: Decodable {
        let did: String
        let handle: String
        let displayName: String?
        let avatar: String?
        let viewer: Viewer?

        struct Viewer: Decodable {
            let following: String?
        }
    }

    struct Record: Decodable {
        let type: String
        let text: String
        let createdAt: String
        let facets: [Facet]?
        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case text
            case createdAt
            case facets
        }
    }

    struct Facet: Decodable {
        let index: FacetIndex
        let features: [Feature]
        struct FacetIndex: Decodable { let byteStart: Int; let byteEnd: Int }
    }

    enum Feature: Decodable {
        case link(uri: String)
        case mention(did: String)
        case tag(tag: String)
        case unknown

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let t = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch t {
            case "app.bsky.richtext.facet#link":
                struct L: Decodable { let uri: String }
                self = .link(uri: try L(from: decoder).uri)
            case "app.bsky.richtext.facet#mention":
                struct M: Decodable { let did: String }
                self = .mention(did: try M(from: decoder).did)
            case "app.bsky.richtext.facet#tag":
                struct T: Decodable { let tag: String }
                self = .tag(tag: try T(from: decoder).tag)
            default:
                self = .unknown
            }
        }
    }

    enum Embed: Decodable {
        case images(ImagesView)
        case video(VideoView)
        case record(RecordView)
        indirect case recordWithMedia(RecordWithMediaView)
        case external(ExternalView)
        case unsupported

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch type {
            case "app.bsky.embed.images#view":
                self = .images(try ImagesView(from: decoder))
            case "app.bsky.embed.video#view":
                self = .video(try VideoView(from: decoder))
            case "app.bsky.embed.record#view":
                self = .record(try RecordView(from: decoder))
            case "app.bsky.embed.recordWithMedia#view":
                self = .recordWithMedia(try RecordWithMediaView(from: decoder))
            case "app.bsky.embed.external#view":
                self = .external(try ExternalView(from: decoder))
            default:
                self = .unsupported
            }
        }
    }

    struct RecordView: Decodable {
        let record: EmbeddedRecord
        enum CodingKeys: String, CodingKey { case record }
    }

    struct ExternalView: Decodable {
        let external: External
        enum CodingKeys: String, CodingKey { case external }

        struct External: Decodable {
            let uri: String
            let title: String
            let description: String
            let thumb: String?
        }
    }

    struct RecordWithMediaView: Decodable {
        let record: EmbeddedRecord
        let media: Embed?
        enum CodingKeys: String, CodingKey { case record, media }
    }

    enum EmbeddedRecord: Decodable {
        case view(ViewRecord)
        case blocked
        case notFound

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "$type")!) ?? ""
            switch type {
            case "app.bsky.embed.record#viewRecord":
                self = .view(try ViewRecord(from: decoder))
            case "app.bsky.embed.record#viewBlocked":
                self = .blocked
            case "app.bsky.embed.record#viewNotFound":
                self = .notFound
            default:
                self = .notFound
            }
        }
    }

    struct ViewRecord: Decodable {
        let uri: String
        let cid: String
        let author: Author
        let value: RecordValue?
        let embeds: [Embed]?
    }

    struct RecordValue: Decodable {
        let text: String?
        let createdAt: String?
        let facets: [Facet]?
    }

    struct ImagesView: Decodable {
        let images: [Image]
        struct Image: Decodable {
            let thumb: String?
            let fullsize: String?
            let alt: String?
        }
    }

    struct VideoView: Decodable {
        let cid: String?
        let playlist: String?
        let thumbnail: String?
        let alt: String?
        let aspectRatio: AspectRatio?
        let isGif: Bool?

        struct AspectRatio: Decodable {
            let width: Int?
            let height: Int?
        }
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
