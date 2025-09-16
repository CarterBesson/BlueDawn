import SwiftUI

struct PostRow: View {
    @Environment(SessionStore.self) private var session
    let post: UnifiedPost
    var showAvatar: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            if !post.media.isEmpty { mediaStrip }
            actionBar
        }
        .padding(.vertical, 8)
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
                ForEach(Array(post.media.enumerated()), id: \.offset) { _, m in
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

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
