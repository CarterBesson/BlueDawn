import SwiftUI

struct PostRow: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openURL) private var openURL
    let post: UnifiedPost
    var showAvatar: Bool = true
    var onOpenProfile: ((Network, String) -> Void)? = nil
    // Open a post (used for quoted/embedded posts)
    var onOpenPost: ((UnifiedPost) -> Void)? = nil
    // New: notify parent when an image is tapped (post + index within post.media)
    var onTapImage: ((UnifiedPost, Int) -> Void)? = nil
    // Notify parent when an external web URL should be opened (non-profile links)
    var onOpenExternalURL: ((URL) -> Void)? = nil
    // When true, use tighter internal padding (timeline supplies outer padding)
    var compactPadding: Bool = false

    @ViewBuilder private var shareBanner: some View {
        if post.isRepostOrBoost, let name = post.boostedByDisplayName ?? post.boostedByHandle {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                Button {
                    let handle = post.boostedByHandle ?? post.authorHandle
                    onOpenProfile?(post.network, handle)
                } label: {
                    Text("\(bannerVerb) \(name)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var crossPostBadge: some View {
        if let alts = post.crossPostAlternates, !alts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "link")
                if alts.keys.contains(where: { if case .bluesky = $0 { return true } else { return false } }) {
                    Image(systemName: "cloud")
                }
                if alts.keys.contains(where: { if case .mastodon = $0 { return true } else { return false } }) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                Text("Also on \(altNames(alts))")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Also posted on \(altNames(alts))")
        }
    }

    private func altNames(_ alts: [Network: String]) -> String {
        var names: [String] = []
        if alts.keys.contains(where: { if case .bluesky = $0 { return true } else { return false } }) { names.append("Bluesky") }
        if alts.keys.contains(where: { if case .mastodon = $0 { return true } else { return false } }) { names.append("Mastodon") }
        return names.joined(separator: " & ")
    }

    private var bannerVerb: String {
        switch post.network {
        case .bluesky: return "Reposted by"
        case .mastodon: return "Boosted by"
        }
    }

    // Background tint handled by container (e.g., TimelineRow)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shareBanner
            crossPostBadge
            header
            content
            if let link = firstExternalLink, !hasAnyMedia, post.quotedPost == nil {
                // Tappable rich link preview (uses environment openURL handler)
                Button {
                    openURL(link)
                } label: {
                    LinkPreviewView(url: link)
                }
                .buttonStyle(.plain)
            }
            if let quoted = post.quotedPost {
                QuotedPostCard(post: quoted, onOpenPost: { q in onOpenPost?(q) }, onOpenProfile: onOpenProfile)
            }
            if !post.media.isEmpty { mediaStrip }
            actionBar
        }
        .padding(.vertical, compactPadding ? 0 : 10)
        .padding(.horizontal, compactPadding ? 0 : 12)
        // Handle taps on links inside attributed text for mentions/user profiles
        .environment(\.openURL, OpenURLAction { url in
            handleOpenURL(url)
        })
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if showAvatar {
                AvatarView(
                    url: post.authorAvatarURL,
                    fallbackText: post.authorHandle,
                    networkIcon: networkIconName,
                    size: 44
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("@\(post.authorHandle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: networkIconName ?? "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(relativeDate(post.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Content
    private var content: some View {
        Text(post.text)
            .font(.body)
            .textSelection(.enabled)
    }

    // MARK: - Media
    private var mediaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(post.media.enumerated()), id: \.offset) { idx, m in
                    Group {
                        switch m.kind {
                        case .image:
                            Button { onTapImage?(post, idx) } label: {
                                AsyncImage(url: m.url) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle().fill(Color.secondary.opacity(0.1))
                                            .overlay(ProgressView())
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Rectangle().fill(Color.secondary.opacity(0.15))
                                            .overlay(Image(systemName: "photo").font(.title3))
                                    @unknown default:
                                        Rectangle().fill(Color.secondary.opacity(0.15))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(m.altText ?? "Image")
                        case .video, .gif:
                            InlineVideoView(url: m.url)
                                .overlay(alignment: .bottomTrailing) {
                                    Button {
                                        NotificationCenter.default.post(name: Notification.Name("InlineVideoPauseAll"), object: nil)
                                        onTapImage?(post, idx)
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(6)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .accessibilityLabel("Open full screen")
                                }
                                .accessibilityLabel(m.altText ?? "Video")
                        }
                    }
                    .frame(width: 160, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Action bar (icon-only, optional counts)
    private var actionBar: some View {
        HStack(spacing: 22) {
            // Reply (stubbed UI action only for now)
            Button {
                // TODO: reply composer
            } label: { actionLabel(symbol: "bubble.left", count: post.counts.replies, label: "Reply") }

            // Repost/Boost
            Button { Task { await handleRepost() } } label: {
                actionLabel(
                    symbol: state.isReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                    count: state.repostCount,
                    label: "Repost",
                    active: state.isReposted
                )
            }

            // Like/Favorite
            Button { Task { await handleLike() } } label: {
                actionLabel(symbol: state.isLiked ? "heart.fill" : "heart", count: state.likeCount, label: "Like", active: state.isLiked)
            }

            // Bookmark (Mastodon only)
            if case .mastodon = post.network {
                Button { Task { await handleBookmark() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: state.isBookmarked ? "bookmark.fill" : "bookmark")
                            .accessibilityLabel("Bookmark")
                            .foregroundStyle(state.isBookmarked ? Color.accentColor : Color.secondary)
                    }
                }
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .buttonStyle(.plain)
    }

    private func actionLabel(symbol: String, count: Int?, label: String, active: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .accessibilityLabel(label)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
            if let s = Formatters.shortCount(count) { Text(s).accessibilityHidden(true) }
        }
    }

    @MainActor private func handleLike() async {
        let s = state
        let prevLiked = s.isLiked
        let prevCount = s.likeCount
        let prevRkey = s.bskyLikeRkey
        if s.isLiked {
            Haptics.impact(.rigid)
            // Unlike
            withAnimation { session.updateState(for: post.id) { $0.isLiked = false; $0.likeCount = max(0, prevCount - 1) } }
            switch post.network {
            case .bluesky:
                do { try await session.blueskyClient?.unlike(post: post, rkey: prevRkey) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
                }
            case .mastodon:
                do { try await session.mastodonClient?.unlike(post: post, rkey: nil) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
                }
            }
            return
        }
        // Like
        Haptics.impact(.light)
        withAnimation { session.updateState(for: post.id) { $0.isLiked = true; $0.likeCount = prevCount + 1 } }
        switch post.network {
        case .bluesky:
            do {
                let rkey = try await session.blueskyClient?.like(post: post)
                withAnimation { session.updateState(for: post.id) { $0.bskyLikeRkey = rkey ?? prevRkey } }
            } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
            }
        case .mastodon:
            do { _ = try await session.mastodonClient?.like(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
            }
        }
    }

    @MainActor private func handleRepost() async {
        let s = state
        let prev = s.isReposted
        let prevCount = s.repostCount
        let prevRkey = s.bskyRepostRkey
        if s.isReposted {
            Haptics.impact(.rigid)
            // Unrepost
            withAnimation { session.updateState(for: post.id) { $0.isReposted = false; $0.repostCount = max(0, prevCount - 1) } }
            switch post.network {
            case .bluesky:
                do { try await session.blueskyClient?.unrepost(post: post, rkey: prevRkey) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
                }
            case .mastodon:
                do { try await session.mastodonClient?.unrepost(post: post, rkey: nil) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
                }
            }
            return
        }
        // Repost
        Haptics.impact(.light)
        withAnimation { session.updateState(for: post.id) { $0.isReposted = true; $0.repostCount = prevCount + 1 } }
        switch post.network {
        case .bluesky:
            do {
                let rkey = try await session.blueskyClient?.repost(post: post)
                withAnimation { session.updateState(for: post.id) { $0.bskyRepostRkey = rkey ?? prevRkey } }
            } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        case .mastodon:
            do { _ = try await session.mastodonClient?.repost(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        }
    }

    @MainActor private func handleBookmark() async {
        guard case .mastodon = post.network else { return }
        let prev = state.isBookmarked
        if state.isBookmarked {
            Haptics.impact(.rigid)
            withAnimation { session.updateState(for: post.id) { $0.isBookmarked = false } }
            do { try await session.mastodonClient?.unbookmark(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isBookmarked = prev } }
            }
        } else {
            Haptics.impact(.light)
            withAnimation { session.updateState(for: post.id) { $0.isBookmarked = true } }
            do { try await session.mastodonClient?.bookmark(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isBookmarked = prev } }
            }
        }
    }

    private var state: PostInteractionState { session.state(for: post) }

    // MARK: - Helpers
    private var displayName: String {
        post.authorDisplayName?.isEmpty == false ? post.authorDisplayName! : post.authorHandle
    }

    private var networkIconName: String? {
        switch post.network {
        case .bluesky: return "cloud"
        case .mastodon: return "dot.radiowaves.left.and.right"
        }
    }

    // First external http(s) link in the attributed text, excluding @-mentions
    private var firstExternalLink: URL? {
        for run in post.text.runs {
            guard let url = run.link,
                  let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else { continue }

            // Heuristic 1: if the visible text for this run starts with '@', treat as a mention and skip
            let range = run.range
            let segment = post.text[range]
            let visible = String(segment.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if visible.hasPrefix("@") { continue }

            // Heuristic 2: skip obvious profile URL shapes
            if let host = url.host?.lowercased() {
                // Bluesky web profile URLs
                if host == "bsky.app" && url.path.lowercased().hasPrefix("/profile/") { continue }
                // Mastodon profile URLs on the same instance (/@user)
                if case .mastodon(let instance) = post.network, host == instance.lowercased(), url.path.hasPrefix("/@") { continue }
            }

            return url
        }
        return nil
    }

    private var hasAnyMedia: Bool { !post.media.isEmpty }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private extension PostRow {
    func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        // Bluesky internal mention links
        if url.scheme == "bluesky" && url.host == "profile" {
            let comps = url.pathComponents.filter { $0 != "/" }
            if let handle = comps.first, !handle.isEmpty {
                onOpenProfile?(.bluesky, handle)
                return .handled
            }
        }

        // Mastodon links (status first, then profile)
        if let scheme = url.scheme, (scheme == "https" || scheme == "http"),
           let host = url.host {
            let path = url.path
            // Mastodon status links: https://host/@user/<id> or /users/<acct>/statuses/<id>
            if let statusID = extractMastoStatusID(fromPath: path) {
                Task { await openMastodonStatus(host: host, id: statusID, originalURL: url) }
                return .handled
            }
            // Mastodon profile links like https://instance/@user
            if path.hasPrefix("/@") {
                let username = String(path.dropFirst(2)) // drop "/@"
                if !username.isEmpty { onOpenProfile?(.mastodon(instance: host), username); return .handled }
            }
            // Mastodon profile style: /users/<acct>
            if path.hasPrefix("/users/") {
                let comps = path.split(separator: "/").map(String.init)
                if comps.count >= 2 {
                    let acct = comps[1]
                    if !acct.isEmpty { onOpenProfile?(.mastodon(instance: host), acct); return .handled }
                }
            }
            // Bluesky web links (profile or post): https://bsky.app/profile/<actor>[/post/<rkey>]
            if host == "bsky.app" && path.hasPrefix("/profile/") {
                let comps = path.split(separator: "/").map(String.init)
                if comps.count >= 4 && comps[0] == "profile" && comps[2] == "post" {
                    let actor = comps[1]
                    let rkey = comps[3]
                    if !actor.isEmpty && !rkey.isEmpty {
                        Task { await openBlueskyStatus(actor: actor, rkey: rkey, originalURL: url) }
                        return .handled
                    }
                }
                if comps.count >= 2 && comps[0] == "profile" {
                    let actor = comps[1]
                    if !actor.isEmpty { onOpenProfile?(.bluesky, actor); return .handled }
                }
            }
        }

        // For other web links, open either in-app Safari or system browser
        if let scheme = url.scheme, (scheme == "https" || scheme == "http") {
            if session.openLinksInApp {
                onOpenExternalURL?(url)
                return .handled
            } else {
                return .systemAction
            }
        }

        return .systemAction
    }

    @MainActor
    func openBlueskyStatus(actor: String, rkey: String, originalURL: URL?) async {
        guard let client = session.blueskyClient else {
            if let u = originalURL { if session.openLinksInApp { onOpenExternalURL?(u) } }
            return
        }
        do {
            if let post = try await client.fetchPost(actorOrHandle: actor, rkey: rkey) {
                onOpenPost?(post)
                return
            }
        } catch {
            // ignore
        }
        if let u = originalURL {
            if session.openLinksInApp {
                onOpenExternalURL?(u)
            }
        }
    }

    func extractMastoStatusID(fromPath path: String) -> String? {
        let comps = path.split(separator: "/").map(String.init)
        if comps.count >= 2, comps[0].hasPrefix("@") {
            let last = comps.last!
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: last)) { return last }
        }
        if let idx = comps.firstIndex(of: "statuses"), idx + 1 < comps.count {
            let cand = comps[idx + 1]
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cand)) { return cand }
        }
        return nil
    }

    @MainActor
    func openMastodonStatus(host: String, id: String, originalURL: URL?) async {
        // Choose client: use signed-in client if same host; otherwise public client
        let client: MastodonClient
        if let c = session.mastodonClient, c.baseURL.host == host {
            client = c
        } else {
            guard let base = URL(string: "https://\(host)") else { return }
            client = MastodonClient(baseURL: base, accessToken: "")
        }
        do {
            if let post = try await client.fetchStatus(id: id) {
                onOpenPost?(post)
                return
            }
        } catch {
            // ignore
        }
        // Fallback: open in-browser if configured
        if let u = originalURL {
            if session.openLinksInApp {
                onOpenExternalURL?(u)
            }
        }
    }
}
