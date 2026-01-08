import Foundation

extension MastodonClient {
    func mapStatusToUnified(_ s: MastoStatus) -> UnifiedPost {
        // Prefer the boosted/original content when this status is a reblog
        let src = s.reblog ?? MastoReblog(
            id: s.id,
            created_at: s.created_at,
            in_reply_to_id: s.in_reply_to_id,
            sensitive: s.sensitive,
            spoiler_text: s.spoiler_text,
            content: s.content,
            account: s.account,
            media_attachments: s.media_attachments
        )
        let isBoost = (s.reblog != nil)
        let boostedName = isBoost ? (s.account.display_name.isEmpty ? nil : s.account.display_name) : nil
        let boostedHandle = isBoost ? s.account.acct : nil

        let created = parseISO8601(src.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(src.content)
        let media: [Media] = src.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        let cwLabels: [UnifiedPost.CWOrLabel]? = {
            var arr: [UnifiedPost.CWOrLabel] = []
            if let spoiler = src.spoiler_text, !spoiler.isEmpty { arr.append(.cw(spoiler)) }
            if src.sensitive == true { arr.append(.label("sensitive")) }
            return arr.isEmpty ? nil : arr
        }()

        // Quoted post (if present)
        let quoted: QuotedPost? = {
            if let q = s.quote { return mapReblogToQuoted(q) }
            return nil
        }()

        return UnifiedPost(
            id: "mastodon:\(src.id)",
            network: .mastodon(instance: baseURL.host ?? baseURL.absoluteString),
            authorHandle: src.account.acct,
            authorDisplayName: src.account.display_name.isEmpty ? nil : src.account.display_name,
            authorAvatarURL: URL(string: src.account.avatar),
            createdAt: created,
            text: text,
            media: media,
            cwOrLabels: cwLabels,
            counts: PostCounts(replies: s.replies_count, boostsReposts: s.reblogs_count, favLikes: s.favourites_count),
            inReplyToID: src.in_reply_to_id,
            isRepostOrBoost: isBoost,
            bskyCID: nil,
            isLiked: s.favourited ?? false,
            isReposted: s.reblogged ?? false,
            isBookmarked: s.bookmarked ?? false,
            boostedByHandle: boostedHandle,
            boostedByDisplayName: boostedName,
            quotedPost: quoted
        )
    }

    // Map a full status to a compact quoted post (no nested quotes/thread fields)
    func mapStatusToQuoted(_ s: MastoStatus, instanceHost: String? = nil) -> QuotedPost {
        let created = parseISO8601(s.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(s.content)
        let media: [Media] = s.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        return QuotedPost(
            id: "mastodon:\(s.id)",
            network: .mastodon(instance: instanceHost ?? (baseURL.host ?? baseURL.absoluteString)),
            authorHandle: s.account.acct,
            authorDisplayName: s.account.display_name.isEmpty ? nil : s.account.display_name,
            authorAvatarURL: URL(string: s.account.avatar),
            createdAt: created,
            text: text,
            media: media
        )
    }

    func mapReblogToQuoted(_ src: MastoReblog) -> QuotedPost {
        let created = parseISO8601(src.created_at) ?? Date()
        let text: AttributedString = HTML.toAttributed(src.content)
        let media: [Media] = src.media_attachments.compactMap { att in
            let kind: Media.Kind
            switch att.type {
            case "image": kind = .image
            case "video": kind = .video
            case "gifv":  kind = .gif
            default:       kind = .image
            }
            guard let u = URL(string: att.url) ?? (att.preview_url.flatMap(URL.init(string:))) else { return nil }
            return Media(url: u, altText: att.description, kind: kind)
        }
        return QuotedPost(
            id: "mastodon:\(src.id)",
            network: .mastodon(instance: baseURL.host ?? baseURL.absoluteString),
            authorHandle: src.account.acct,
            authorDisplayName: src.account.display_name.isEmpty ? nil : src.account.display_name,
            authorAvatarURL: URL(string: src.account.avatar),
            createdAt: created,
            text: text,
            media: media
        )
    }
}
