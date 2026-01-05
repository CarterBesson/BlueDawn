import Foundation

extension BlueskyClient {
    func flatten(_ list: [ThreadUnion], into out: inout [ThreadItem], depth: Int) {
        for entry in list {
            switch entry {
            case .threadViewPost(let node):
                let u = mapPostToUnified(node.post)
                out.append(ThreadItem(id: u.id, post: u, depth: depth))
                if let replies = node.replies, !replies.isEmpty {
                    flatten(replies, into: &out, depth: depth + 1)
                }
            default:
                continue
            }
        }
    }

    func mapPostToUnified(_ p: Post, isRepost: Bool = false, boostedByHandle: String? = nil, boostedByDisplayName: String? = nil) -> UnifiedPost {
        let created = parseISO8601(p.record?.createdAt ?? p.indexedAt ?? "") ?? Date()
        let text = attributedFromBsky(text: p.record?.text ?? "", facets: p.record?.facets)
        var media: [Media] = []
        var quoted: QuotedPost? = nil
        var externalURL: URL? = nil
        if let embed = p.embed {
            switch embed {
            case .images(let view):
                media = view.images.compactMap { img in
                    guard let url = URL(string: img.fullsize ?? img.thumb ?? "") else { return nil }
                    return Media(url: url, altText: img.alt, kind: .image)
                }
            case .video(let view):
                if let videoMedia = mediaFromVideo(view) {
                    media = [videoMedia]
                }
            case .record(let rv):
                if case .view(let r) = rv.record { quoted = mapEmbeddedRecordToQuoted(r) }
            case .recordWithMedia(let rwm):
                if case .view(let r) = rwm.record {
                    var quotedMedia: [Media] = []
                    if let m = rwm.media {
                        switch m {
                        case .images(let view):
                            quotedMedia = view.images.compactMap { img in
                                guard let url = URL(string: img.fullsize ?? img.thumb ?? "") else { return nil }
                                return Media(url: url, altText: img.alt, kind: .image)
                            }
                        case .video(let view):
                            if let vm = mediaFromVideo(view) { quotedMedia = [vm] }
                        default:
                            break
                        }
                    }
                    quoted = mapEmbeddedRecordToQuoted(r, media: quotedMedia)
                }
            case .external(let extView):
                externalURL = URL(string: extView.external.uri)
            case .unsupported:
                break
            }
        }
        let counts = PostCounts(
            replies: p.replyCount,
            boostsReposts: p.repostCount,
            favLikes: p.likeCount
        )
        let (isLiked, likeRkey): (Bool, String?) = {
            if let likeUri = p.viewer?.like, let r = Self.extractRkey(fromAtUri: likeUri) { return (true, r) }
            return (false, nil)
        }()
        let (isReposted, repostRkey): (Bool, String?) = {
            if let rpUri = p.viewer?.repost, let r = Self.extractRkey(fromAtUri: rpUri) { return (true, r) }
            return (false, nil)
        }()

        return UnifiedPost(
            id: "bsky:\(p.uri)",
            network: .bluesky,
            authorHandle: p.author.handle,
            authorDisplayName: p.author.displayName,
            authorAvatarURL: URL(string: p.author.avatar ?? ""),
            createdAt: created,
            text: text,
            media: media,
            cwOrLabels: nil,
            counts: counts,
            inReplyToID: nil,
            isRepostOrBoost: isRepost,
            bskyCID: p.cid,
            bskyLikeRkey: likeRkey,
            bskyRepostRkey: repostRkey,
            isLiked: isLiked,
            isReposted: isReposted,
            isBookmarked: false,
            boostedByHandle: boostedByHandle,
            boostedByDisplayName: boostedByDisplayName,
            externalURL: externalURL,
            quotedPost: quoted
        )
    }

    func mediaFromVideo(_ video: VideoView) -> Media? {
        guard let playlist = video.playlist, let url = URL(string: playlist) else { return nil }
        let kind: Media.Kind = (video.isGif ?? false) ? .gif : .video
        return Media(url: url, altText: video.alt, kind: kind)
    }

    func mapEmbeddedRecordToQuoted(_ r: ViewRecord, media: [Media] = []) -> QuotedPost {
        let created = parseISO8601(r.value?.createdAt ?? "") ?? Date()
        let text = attributedFromBsky(text: r.value?.text ?? "", facets: r.value?.facets)

        var quotedMedia = media
        if let embeds = r.embeds {
            for embed in embeds {
                switch embed {
                case .images(let view):
                    let embedMedia: [Media] = view.images.compactMap { img in
                        guard let url = URL(string: img.fullsize ?? img.thumb ?? "") else { return nil }
                        return Media(url: url, altText: img.alt, kind: .image)
                    }
                    quotedMedia.append(contentsOf: embedMedia)
                case .video(let view):
                    if let vm = mediaFromVideo(view) { quotedMedia.append(vm) }
                default:
                    break
                }
            }
        }

        return QuotedPost(
            id: "bsky:\(r.uri)",
            network: .bluesky,
            authorHandle: r.author.handle,
            authorDisplayName: r.author.displayName,
            authorAvatarURL: URL(string: r.author.avatar ?? ""),
            createdAt: created,
            text: text,
            media: quotedMedia
        )
    }

    func parseISO8601(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: s) ?? f2.date(from: s)
    }
}
